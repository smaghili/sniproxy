# راهنمای نصب و راه‌اندازی DNS Proxy (برای کاهش پینگ و رفع تحریم ها )

## مقدمه
این راهنما شامل مراحل نصب و پیکربندی یک تانل با استفاده از WireGuard، بهینه‌سازی سرور، و راه‌اندازی DNS پروکسی است. این فرآیند شامل تنظیمات در دو سرور (ایران و خارج) می‌باشد.

## فهرست مطالب
1. [آماده‌سازی سرورها](#1-آماده‌سازی-سرورها)
2. [بهینه‌سازی سرورها](#2-بهینه‌سازی-سرورها)
3. [نصب و پیکربندی WireGuard](#3-نصب-و-پیکربندی-wireguard)
4. [نصب DNS پروکسی](#4-نصب-dns-پروکسی)

## 1. آماده‌سازی سرورها
- اطمینان حاصل کنید که روی هر دو سرور (ایران و خارج) لینوکس نسخه اوبونتو 20 یا 22 نصب باشد.
- هر دو سرور را با دستور زیر به‌روزرسانی کنید:
  ```
  apt update -y && apt upgrade -y
  ```

## 2. بهینه‌سازی سرورها
1. دستور زیر را روی هر دو سرور اجرا کنید:
   ```
   apt install curl -y && bash <(curl -s https://raw.githubusercontent.com/opiran-club/VPS-Optimizer/main/optimizer.sh --ipv4)
   ```
2. از منوی نمایش داده شده، گزینه 1 (Optimizer (1-click)) را انتخاب کنید.
3. در مرحله انتخاب TCP Congestion Control، گزینه 1 (TCP-BBR (Basic BBR)) را انتخاب کنید.
4. وقتی پیام "Press any key to start...or Press Ctrl+C to cancel" نمایش داده شد، Enter بزنید.
5. در پیام ریستارت، 'y' را وارد کنید تا سیستم ریبوت شود.
6. صبر کنید تا سرور مجدداً راه‌اندازی شود.

## 3. نصب و پیکربندی WireGuard
1. روی هر دو سرور دستور زیر را اجرا کنید:
   ```
   curl -o install.sh https://raw.githubusercontent.com/smaghili/WireGuard-Tunnel/main/install.sh && chmod +x install.sh && ./install.sh
   ```

### پیکربندی سرور خارج:
1. از منو، گزینه 1 (Configure WireGuard Server) را انتخاب کنید.
2. IP سرور و کلید عمومی نمایش داده شده را یادداشت کنید.

### پیکربندی سرور ایران:
1. از منو، گزینه 2 (Configure WireGuard Client) را انتخاب کنید.
2. کلید عمومی سرور خارج را وارد کنید.
3. IP سرور خارج را وارد کنید.
4. کلید عمومی سرور ایران را که نمایش داده می‌شود، یادداشت کنید.

### تکمیل پیکربندی در سرور خارج:
1. به سرور خارج برگردید.
2. از منو، گزینه 3 (Add Client To Peers) را انتخاب کنید.
3. کلید عمومی سرور ایران را وارد کنید.

### راه‌اندازی نهایی:
1. در هر دو سرور، از منو گزینه 6 را انتخاب کنید تا تونل‌ها ریستارت شوند.
2. 30 ثانیه صبر کنید.
3. در سرور ایران، دستور زیر را اجرا کنید:
   ```
   curl ipconfig.io
   ```
   اگر IP سرور خارج نمایش داده شود، تونل با موفقیت برقرار شده است.

## 4. نصب DNS پروکسی

### روش اول: نصب از طریق GitHub

#### نصب در سرور ایران:
```
bash <(curl -L https://raw.githubusercontent.com/smaghili/sniproxy/master/simpleinstall.sh)
```

#### نصب در سرور خارج:
```
bash <(curl -L https://raw.githubusercontent.com/smaghili/sniproxy/master/installkharej.sh)
```

### روش دوم: نصب از طریق فایل

این مراحل را در هر دو سرور ایران و خارج انجام دهید:

1. انتقال فایل:
   - فایل زیپ تحویلی را به هر دو سرور ایران و خارج منتقل کنید. ترجیحاً در روت سرور قرار دهید.

2. نصب unzip (در صورت نیاز):
   ```
   apt install unzip
   ```

3. استخراج فایل‌ها:
   ```
   unzip sniproxy.zip
   ```

4. اعطای مجوز اجرا:
   ```
   chmod +x -R sniproxy-master
   ```

5. ورود به پوشه پروژه:
   ```
   cd sniproxy-master
   ```

6. اجرای اسکریپت نصب:
   - در سرور ایران:


   ```
   ./simpleinstall.sh
   ```
     
   - در سرور خارج:

   ```
   ./installkharej.sh
   ```

### بررسی نصب:
- در سرور ایران، پیامی مشابه زیر نشان دهنده نصب موفق است:
  ```
  sniproxy is running
  sniproxy is now running, you can set up DNS in your clients to [IP_ADDRESS]
  ...
  ```

- در سرور خارج، پیامی مشابه زیر نشان دهنده نصب موفق است:
  ```
  Web Panel Running on http://[IP_ADDRESS]:5000
  DNS service is successfully running on 0.0.0.0:53 
  Setup completed!
  ```

### آدرس دسترسی به پنل مدیریت:
```
http://[YOUR_IP_SERVER]:5000
```
(به جای [YOUR_IP_SERVER] باید IP سرور خارج خود را وارد کنید)

- نام کاربری: `admin`
- رمز عبور: `password`

### اضافه کردن IP:
برای اضافه کردن IP از سمت مشتری، از آدرس زیر استفاده کنید:
```
http://[YOUR_IP_SERVER]:5000/addip
```
(به جای `[YOUR_IP_SERVER]` باید IP سرور خارج خود را وارد کنید)
