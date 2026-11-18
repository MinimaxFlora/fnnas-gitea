#!/usr/bin/env python3
"""SMTP 连通性与投递测试

用法：
  SMTP_PASSWD='******' python3 smtp_test.py \
      --host smtp.example.com --port 465 --mode smtps \
      --user gitea@example.com --sender 'Gitea <gitea@example.com>' [--skip-verify]

退出码：0 成功；2 认证失败；3 连接/TLS 失败；4 其它发送失败
"""

import argparse
import email.message
import email.utils
import os
import smtplib
import ssl
import sys


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", default="465")
    ap.add_argument("--mode", default="smtps",
                    choices=["smtps", "starttls", "smtp"])
    ap.add_argument("--user", default="")
    ap.add_argument("--sender", required=True)
    ap.add_argument("--to", default="")
    ap.add_argument("--skip-verify", action="store_true")
    ap.add_argument("--timeout", type=int, default=12)
    args = ap.parse_args()

    passwd = os.environ.get("SMTP_PASSWD", "")
    sender_name, sender_addr = email.utils.parseaddr(args.sender)
    if not sender_addr:
        die(4, "发件人地址无效：%s" % args.sender)
    rcpt = email.utils.parseaddr(args.to)[1] or sender_addr

    ctx = ssl.create_default_context()
    if args.skip_verify:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    server = None
    try:
        if args.mode == "smtps":
            server = smtplib.SMTP_SSL(args.host, int(args.port), timeout=args.timeout, context=ctx)
        else:
            server = smtplib.SMTP(args.host, int(args.port), timeout=args.timeout)
            server.ehlo()
            if args.mode == "starttls":
                server.starttls(context=ctx)
                server.ehlo()
    except ssl.SSLError as e:
        die(3, "TLS 握手失败（%s:%s，%s）：%s\n提示：465 端口通常用 SMTPS，587 用 STARTTLS"
            % (args.host, args.port, args.mode, e))
    except (smtplib.SMTPException, OSError) as e:
        die(3, "无法连接 %s:%s（%s）：%s\n提示：检查地址/端口/加密方式，以及 NAS 出网与防火墙"
            % (args.host, args.port, args.mode, e))

    if server is None:  # 理论不可达，die() 已经退出
        die(3, "无法建立 SMTP 连接")

    try:
        if args.user:
            try:
                server.login(args.user, passwd)
            except smtplib.SMTPAuthenticationError as e:
                die(2, "SMTP 认证失败（%s）：%s %s\n提示：用户名/密码错误，或该服务器要求授权码"
                    % (args.user, getattr(e, "smtp_code", ""), getattr(e, "smtp_error", b"")))

        msg = email.message.EmailMessage()
        msg["From"] = args.sender
        msg["To"] = rcpt
        msg["Subject"] = "fnOS Gitea SMTP 测试邮件"
        msg.set_content(
            "这是一封来自飞牛 fnOS Gitea 应用的 SMTP 测试邮件。\n"
            "收到它说明 SMTP 配置可用，可以删掉这封邮件。\n"
        )
        server.send_message(msg, from_addr=sender_addr, to_addrs=[rcpt])
    except smtplib.SMTPException as e:
        die(4, "发送失败：%s" % e)
    finally:
        try:
            server.quit()
        except Exception:
            pass

    print("SMTP 测试通过：%s:%s（%s），已投递测试邮件到 %s" % (args.host, args.port, args.mode, rcpt))


if __name__ == "__main__":
    main()
