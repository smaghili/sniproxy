import os
import yaml
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
import subprocess
from functools import wraps
import requests
import logging

# تنظیم لاگینگ
logging.basicConfig(filename='/var/log/web_panel.log', level=logging.INFO,
                    format='%(asctime)s %(levelname)s: %(message)s')

app = Flask(__name__)
app.secret_key = os.urandom(24)  # Use a random secret key for better security

INSTALL_DIR = "/opt/sniproxy"
WHITELIST_FILE = f"{INSTALL_DIR}/domains.csv"
ALLOWED_IPS_FILE = f"{INSTALL_DIR}/cidr.csv"
SNIPROXY_CONFIG = f"{INSTALL_DIR}/sniproxy.yaml"

# Get panel port, username and password from environment variables
PANEL_PORT = int(os.environ.get('PANEL_PORT', 5000))
ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'password')

# لاگ کردن مقادیر (بدون نمایش رمز عبور)
logging.info(f"PANEL_PORT: {PANEL_PORT}")
logging.info(f"ADMIN_USERNAME: {ADMIN_USERNAME}")
logging.info("ADMIN_PASSWORD is set")

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated_function

def run_command(command):
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        logging.error(f"Command failed: {e.stderr}")
        raise Exception(f"Command failed: {e.stderr}")

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session['logged_in'] = True
            return redirect(url_for('index'))
        else:
            return render_template('login.html', error='Invalid credentials')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect(url_for('login'))

@app.route('/')
@login_required
def index():
    return render_template('index.html')

@app.route('/api/status')
@login_required
def get_status():
    try:
        status = run_command("systemctl is-active sniproxy.service")
    except Exception:
        status = "inactive"
    
    try:
        with open(SNIPROXY_CONFIG, 'r') as f:
            config = yaml.safe_load(f)
        
        mode = "DNS Allow All" if not config['acl']['domain']['enabled'] else "Whitelist"
        ip_restriction = "ACTIVE" if config['acl']['cidr']['enabled'] else "INACTIVE"
    except Exception as e:
        logging.error(f"Error reading config: {str(e)}")
        mode = "Unknown"
        ip_restriction = "Unknown"
    
    return jsonify({
        "status": status, 
        "mode": mode,
        "ip_restriction": ip_restriction
    })

@app.route('/api/toggle', methods=['POST'])
@login_required
def toggle_service():
    action = request.json['action']
    mode = request.json.get('mode', '')
    
    if mode == 'dns-allow-all':
        update_sniproxy_config(False)
    elif mode == 'whitelist':
        update_sniproxy_config(True)
    
    try:
        if action == 'start':
            run_command("systemctl start sniproxy.service")
        elif action == 'stop':
            run_command("systemctl stop sniproxy.service")
        elif action == 'restart':
            run_command("systemctl restart sniproxy.service")
        else:
            return jsonify({"error": "Invalid action"}), 400
        
        return jsonify({"result": f"Service {action}ed successfully"})
    except Exception as e:
        logging.error(f"Error toggling service: {str(e)}")
        return jsonify({"error": str(e)}), 500

def update_sniproxy_config(enable_domain):
    try:
        with open(SNIPROXY_CONFIG, 'r') as f:
            config = yaml.safe_load(f)
        
        config['acl']['domain']['enabled'] = enable_domain
        
        with open(SNIPROXY_CONFIG, 'w') as f:
            yaml.dump(config, f)
        
        run_command("systemctl restart sniproxy.service")
    except Exception as e:
        logging.error(f"Failed to update config: {str(e)}")
        raise Exception(f"Failed to update config: {str(e)}")

def update_sniproxy_config_ip(enable_ip):
    try:
        with open(SNIPROXY_CONFIG, 'r') as f:
            config = yaml.safe_load(f)
        
        config['acl']['cidr']['enabled'] = enable_ip
        
        with open(SNIPROXY_CONFIG, 'w') as f:
            yaml.dump(config, f)
        
        run_command("systemctl restart sniproxy.service")
    except Exception as e:
        logging.error(f"Failed to update IP config: {str(e)}")
        raise Exception(f"Failed to update IP config: {str(e)}")

@app.route('/api/toggle_ip_restriction', methods=['POST'])
@login_required
def toggle_ip_restriction():
    action = request.json['action']
    try:
        if action == 'enable':
            update_sniproxy_config_ip(True)
        else:
            update_sniproxy_config_ip(False)
        
        return jsonify({"result": f"IP restriction {action}d and service restarted"})
    except Exception as e:
        logging.error(f"Error toggling IP restriction: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/whitelist')
@login_required
def get_whitelist():
    try:
        with open(WHITELIST_FILE, 'r') as f:
            domains = f.read().splitlines()
        # Remove ',suffix' from each domain and any trailing dots
        domains = [domain.split(',')[0].rstrip('.') for domain in domains]
        return jsonify({"domains": domains})
    except Exception as e:
        logging.error(f"Error getting whitelist: {str(e)}")
        return jsonify({"error": "Failed to get whitelist"}), 500

@app.route('/api/whitelist', methods=['POST'])
@login_required
def update_whitelist():
    try:
        domains = request.json['domains']
        # Add ',suffix' to each domain and ensure it ends with a dot
        formatted_domains = [f"{domain.rstrip('.')}.,suffix" for domain in domains]
        
        with open(WHITELIST_FILE, 'w') as f:
            f.write('\n'.join(formatted_domains))
        
        run_command("systemctl restart sniproxy.service")
        return jsonify({"result": "Whitelist updated and service restarted"})
    except Exception as e:
        logging.error(f"Error updating whitelist: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/allowed_ips')
@login_required
def get_allowed_ips():
    try:
        with open(ALLOWED_IPS_FILE, 'r') as f:
            ips = f.read().splitlines()
        # Filter out 0.0.0.0 and remove CIDR notation and ',allow'
        filtered_ips = [ip.split('/')[0] for ip in ips if not ip.startswith('0.0.0.0') and ',allow' in ip]
        return jsonify({"ips": filtered_ips})
    except Exception as e:
        logging.error(f"Error getting allowed IPs: {str(e)}")
        return jsonify({"error": "Failed to get allowed IPs"}), 500

@app.route('/api/allowed_ips', methods=['POST'])
@login_required
def update_allowed_ips():
    try:
        new_ips = request.json['ips']
        with open(ALLOWED_IPS_FILE, 'r') as f:
            existing_ips = f.read().splitlines()
        
        # Keep 0.0.0.0/0,reject if it exists
        reject_all = next((ip for ip in existing_ips if ip.startswith('0.0.0.0')), None)
        
        # Format new IPs
        formatted_ips = [f"{ip}/32,allow" for ip in new_ips]
        
        # Combine formatted IPs with reject_all if it exists
        if reject_all:
            formatted_ips.append(reject_all)
        
        with open(ALLOWED_IPS_FILE, 'w') as f:
            f.write('\n'.join(formatted_ips))
        
        run_command("systemctl restart sniproxy.service")
        return jsonify({"result": "Allowed IPs updated and service restarted"})
    except Exception as e:
        logging.error(f"Error updating allowed IPs: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/addip')
def addip():
    return render_template('addip.html')

@app.route('/api/client_ip')
def get_client_ip():
    return jsonify({'ip': request.remote_addr})

@app.route('/api/check_ip')
def check_ip():
    ip = request.args.get('ip')
    try:
        with open(ALLOWED_IPS_FILE, 'r') as f:
            ips = f.read().splitlines()
        exists = any(line.startswith(f"{ip}/32,allow") for line in ips)
        return jsonify({'exists': exists})
    except Exception as e:
        logging.error(f"Error checking IP: {str(e)}")
        return jsonify({"error": "Failed to check IP"}), 500

@app.route('/api/add_ip', methods=['POST'])
def add_ip():
    new_ip = request.json['ip']
    try:
        with open(ALLOWED_IPS_FILE, 'r') as f:
            ips = f.read().splitlines()
        
        # Check if IP already exists
        if any(line.startswith(f"{new_ip}/32,allow") for line in ips):
            return jsonify({'success': False, 'error': 'IP already exists'})
        
        # Add new IP
        ips.append(f"{new_ip}/32,allow")
        
        # Ensure 0.0.0.0/0,reject is at the end
        ips = [ip for ip in ips if not ip.startswith('0.0.0.0')]
        ips.append('0.0.0.0/0,reject')
        
        with open(ALLOWED_IPS_FILE, 'w') as f:
            f.write('\n'.join(ips))
        
        run_command("systemctl restart sniproxy.service")
        return jsonify({'success': True})
    except Exception as e:
        logging.error(f"Error adding IP: {str(e)}")
        return jsonify({'success': False, 'error': str(e)})

def get_server_public_ip():
    try:
        response = requests.get('https://ipconfig.io/ip', timeout=5)
        return response.text.strip()
    except:
        logging.error("Failed to get server public IP")
        return None

@app.route('/api/server_ip')
def api_server_ip():
    server_ip = get_server_public_ip()
    return jsonify({'server_ip': server_ip})

@app.route('/api/get_public_ip')
def get_public_ip():
    try:
        response = requests.get('https://ipconfig.io/ip', timeout=5)
        if response.status_code == 200:
            return jsonify({'ip': response.text.strip()})
        else:
            logging.error(f"Failed to get public IP, status code: {response.status_code}")
            return jsonify({'error': 'Failed to get public IP'}), 500
    except requests.RequestException as e:
        logging.error(f"Request failed when getting public IP: {str(e)}")
        return jsonify({'error': f'Request failed: {str(e)}'}), 500

# Debug route to check environment variables
@app.route('/debug_env')
def debug_env():
    return jsonify({
        'PANEL_PORT': PANEL_PORT,
        'ADMIN_USERNAME': ADMIN_USERNAME,
        'ADMIN_PASSWORD': '*' * len(ADMIN_PASSWORD)  # Mask the password
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PANEL_PORT)
else:
    gunicorn_logger = logging.getLogger('gunicorn.error')
    app.logger.handlers = gunicorn_logger.handlers
    app.logger.setLevel(gunicorn_logger.level)
