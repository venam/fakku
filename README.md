#Fakku Downloader, Manager, & Encrypter

###Depends
Perl Module: Net::Curl::Easy <br>
ccrypt program (Tested with version 1.10) <br>
An external download manager (default axel) <br>

###example of usage:

List results: <br>
`./fakku_dl.pl --list --search "milk"` <br>
Download and Encrypt <br>
`./fakku_dl.pl --download --search "milk" --location /home/user/downloads/.hiddenshit/ --encrypt /home/user/password_file` <br>


