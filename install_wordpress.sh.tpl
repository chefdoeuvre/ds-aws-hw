#! /bin/bash
sudo apt update
sudo apt install apache2 wordpress php libapache2-mod-php php-mysql git binutils -y
sudo sh -c 'echo "Alias /blog /usr/share/wordpress
<Directory /usr/share/wordpress>
    Options FollowSymLinks
    AllowOverride Limit Options FileInfo
    DirectoryIndex index.php
    Order allow,deny
    Allow from all
</Directory>
<Directory /usr/share/wordpress/wp-content>
    Options FollowSymLinks
    Order allow,deny
    Allow from all
</Directory>" > /etc/apache2/sites-available/wordpress.conf'
sudo a2ensite wordpress
sudo a2enmod rewrite
sudo service apache2 reload
echo "<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'username');
define('DB_PASSWORD', 'Passw0rd');
define('DB_HOST', '${db_host}');
define('DB_COLLATE', 'utf8_general_ci');
define('WP_CONTENT_DIR', '/usr/share/wordpress/wp-content');
?>" | sudo tee /etc/wordpress/config-eu-west-2.elb.amazonaws.com.php
sudo git clone https://github.com/aws/efs-utils
cd efs-utils
./build-deb.sh
sudo apt-get -y install ./build/amazon-efs-utils*deb
sudo mkdir /efs
sudo mount -t efs -o tls ${efs_dns}:/ efs
