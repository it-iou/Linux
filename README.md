# Linux
Linux常用脚本
## 修改SSH密码

这个脚本用于配置SSH并设置root用户的密码以及SSH端口。


## 一键脚本
```bash
wget -q root.sh https://raw.githubusercontent.com/it-iou/Linux/main/root.sh && chmod +x root.sh && ./root.sh
```

```bash
curl -sS -o root.sh https://raw.githubusercontent.com/it-iou/Linux/main/root.sh && chmod +x root.sh && ./root.sh
```
## 详细说明
- 脚本会根据识别系统然后根据用户选择，生成随机密码或端口同时也支持设置自定义密码和端口，并将其应用于root用户。

- 脚本会修改SSH服务器的配置文件以允许root用户登录和使用密码进行身份验证，并重启SSH服务以应用更改。
## 注意事项
- 在使用脚本之前，请确保您拥有管理员权限。

- 在执行脚本之前，请确保您了解脚本的操作，并且备份您的系统或者重要数据。

- 如果您在使用过程中遇到任何问题或者有任何建议，请随时提交GitHub Issues。
