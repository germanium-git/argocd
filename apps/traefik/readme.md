# Password protection for the dashboard

The secret used in the middleware to protect from unauthorized access cosists of two parts, the <username>:<md5 encoded passord>

For example:
admin:$apr1$cpytdPSt$ThKHEIY7krGcL4AorTA7r.

To generate a password with a random salt the following command can be used:
```
openssl passwd -apr1 admin
$apr1$xWEQDX2M$1/mGx4pwRAlIA5cdPRQt31
```

And to check the current hashed password use the provided salt from teh secret (see the second part between $ signs).
```
openssl passwd -apr1 -salt cpytdPSt admin
$apr1$cpytdPSt$ThKHEIY7krGcL4AorTA7r.
```
