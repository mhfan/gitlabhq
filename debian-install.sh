#!/bin/bash
 ################################################################
 # $ID: debian-install.sh     Thu, 09 May 2013 18:06:30 +0800 $ #
 #                                                              #
 # Description:                                                 #
 #                                                              #
 # Maintainer:  ∑∂√¿ª‘(MeiHui FAN)  <mhfan@ustc.edu>            #
 #                                                              #
 # CopyLeft (c)  2013  M.H.Fan                                  #
 #   All rights reserved.                                       #
 #                                                              #
 # This file is free software;                                  #
 #   you are free to modify and/or redistribute it  	        #
 #   under the terms of the GNU General Public Licence (GPL).   #
 ################################################################

[ 0 -lt $(id -u) ] && echo "Please run in root environment!" && exit 1

HOST_FQDN=127.0.0.1;
#HOST_FQDN=10.12.3.160;

DB_PASSWORD=$(makepasswd)
GITLAB_DIR=/home/gitlab;
GITLAB_USR=gitlab;

true && mkdir -p /srv/gitlab && ln -sf /srv/gitlab $GITLAB_DIR

service gitlab stop;
service nginx  stop;

if false; then # XXX: for upgrade
sudo -u $GITLAB_USR -H sh -c "
cd $GITLAB_DIR/gitlab-shell &&
    git stash && git fetch && git rebase && git stash pop;
cd $GITLAB_DIR/gitlab &&
    git stash && git fetch && git rebase && git stash pop;

bundle install --deployment --without development test postgres &&
bundle exec rake db:migrate RAILS_ENV=production;
"

service gitlab start;
service nginx  start;

exit 0;
fi

#apt-get update && apt-get upgrade	# XXX:

true && apt-get install -y \
    build-essential gcc checkinstall make \
    libc6-dev libssl-dev zlib1g-dev libicu-dev libxml2-dev libxslt-dev \
    libsqlite3-dev libmysql++-dev libcurl4-openssl-dev libreadline6-dev \
    python-dev python-pip libyaml-dev libpq-dev \
    libgdbm-dev libncurses5-dev libffi-dev \
    sudo vim python openssh-server redis-server makepasswd \
    git git-core sqlite3 curl #wget #postfix \

ln -s /usr/bin/python /usr/bin/python2

RUBY_VER=1.9.3-p392; # XXX: 2.0.0-p0
RUBY_PKG=ruby-${RUBY_VER}.tar.gz;
test "$(ruby --version | cut -d \  -f 2)" != "$(echo $RUBY_VER | tr -d -)" &&
mkdir -p /tmp/ruby && cd /tmp/ruby &&
(test -e /tmp/$RUBY_PKG || (echo "Downloading $RUBY_PKG:" &&
\curl --progress http://ftp.ruby-lang.org/pub/ruby/$(echo $RUBY_VER | \
    cut -d . -f 1).$(echo $RUBY_VER | cut -d . -f 2)/$RUBY_PKG \
    -o /tmp/$RUBY_PKG)) && tar xzf /tmp/$RUBY_PKG &&
cd ruby-$RUBY_VER && ./configure && make && make install &&
rm -rf /tmp/ruby

adduser --disabled-login --gecos 'GitLab' --home $GITLAB_DIR $GITLAB_USR

#    -e \"s,http://localhost,https://$HOST_FQDN/gitlab,\" \

sudo -u $GITLAB_USR -H sh -c "
cd $GITLAB_DIR && git clone https://github.com/gitlabhq/gitlab-shell.git;
cd gitlab-shell &&
sed -e \"s/#\?\s*user: git/user: $GITLAB_USR/\" \
    -e \"s,/home/git,$GITLAB_DIR,g\" \
    config.yml.example > config.yml &&
sed -i -e \"s,/home/git,$GITLAB_DIR,\" support/*.sh \
    spec/gitlab_shell_spec.rb &&
bin/install;
"

# XXX: or gitolite?

echo "Please type password for MySQL root account." &&
mysql -u root -p << EOF
#DROP USER '$GITLAB_USR'@'localhost';
#DROP SCHEMA \`gitlabhq_production\`;
##DROP DATABASE \`gitlabhq_production\`;

CREATE USER '$GITLAB_USR'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
#SET PASSWORD FOR '$GITLAB_USR'@'localhost' = PASSWORD('$DB_PASSWORD');

CREATE DATABASE IF NOT EXISTS \`gitlabhq_production\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;
GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON \`gitlabhq_production\`.* TO '$GITLAB_USR'@'localhost';

FLUSH PRIVILEGES;
EOF

#    -e  's/\(port:\) 80/\1 443/; s/\(https:\) false/\1 true/' \

sudo -u $GITLAB_USR -H sh -c "
cd $GITLAB_DIR && git clone https://github.com/gitlabhq/gitlabhq.git gitlab;
cd gitlab &&
sed -e \"s/#\?\s*user: git/user: $GITLAB_USR/\" \
    -e \"s,/home/git,$GITLAB_DIR,g; s/\(host:\) localhost/\1 $HOST_FQDN/\" \
    -e  's/\(wiki:\) true/\1 false/' \
    -e  's,#\s*\(relative_url_root: \).*,\1/gitlab,' \
    config/gitlab.yml.example > config/gitlab.yml &&
sed -e \"s,/home/git,$GITLAB_DIR,g\" \
    -e  's,#\s*\(.\+RELATIVE_URL_ROOT.\+\s*=\).*,\1 \"/gitlab\",' \
    config/puma.rb.example > config/puma.rb &&
sed -e \"s/secure password/$DB_PASSWORD/g\" \
    -e \"s/username: root/username: $GITLAB_USR/g\" \
    config/database.yml.mysql > config/database.yml &&
mkdir -p $GITLAB_DIR/gitlab-satellites &&
mkdir -p       tmp/pids tmp/sockets public/uploads &&
chmod -R u+rwX tmp/pids tmp/sockets public/uploads tmp log;

git config --global user.name  \"GitLab\" &&
git config --global user.email \"$GITLAB_USR@localhost\";
"

cd $GITLAB_DIR/gitlab &&
sed -e "s,/home/git,$GITLAB_DIR,g; s/APP_USER=.*/APP_USER=$GITLAB_USR/" \
    -e '/STOP_SIDEKIQ="RAILS/a STOP_SIDEKIQ="$STOP_SIDEKIQ; rm -f $PID_PATH/../sockets/* $SIDEKIQ_PID"' \
    -e "/restart()/,/}/s/exit 1/start/; s/bash -l/bash/g" \
    lib/support/init.d/gitlab > gitlab &&
install gitlab /etc/init.d/ &&
sed -e "s,/home/git,$GITLAB_DIR,g; s/YOUR_SERVER_FQDN/$HOST_FQDN/g" \
    -e "s,location / ,location /gitlab ,; s/YOUR_SERVER_IP://g" \
    lib/support/nginx/gitlab  > gitlab &&
mv gitlab /etc/nginx/sites-available/ && update-rc.d gitlab defaults 21

true && echo "Installing gems:" &&
gem install bundler &&
gem install charlock_holmes --version '0.6.9.4'	# XXX:

sudo -u $GITLAB_USR -H sh -c "
bundle install --deployment --without development test postgres &&
bundle exec rake gitlab:setup RAILS_ENV=production;

bundle exec rake db:migrate RAILS_ENV=production;
bundle exec rake db:seed_fu RAILS_ENV=production;
# admin@local.host, 5iveL!fe
bundle exec rake gitlab:import:repos RAILS_ENV=production;

#bundle exec rake gitlab:env:info RAILS_ENV=production;
"

sudo -u $GITLAB_USR -H sh -c "
echo mhfan@hhcn.com > $GITLAB_DIR/.forward;
#restorecon $GITLAB_DIR/.forward;
"
/etc/init.d/gitlab restart && service nginx restart

sudo -u $GITLAB_USR -H sh -c "
#bundle exec rake gitlab:check RAILS_ENV=production;
"

exit 0;	# XXX:

#GITLAB_DIR=${GITLAB_DIR}_ci
#GITLAB_USR=${GITLAB_USR}_ci
#DB_PASSWORD=$(makepasswd)

adduser --disabled-login --gecos 'GitLab CI' --home $GITLAB_DIR $GITLAB_USR

false && sudo -u $GITLAB_USR -H sh -c "
echo \"Download & install Ruby (RVM):\";
grep -q \"scripts/rvm\" ||
\curl -L https://get.rvm.io | bash -s stable --ruby &&
    echo \"source ~/.rvm/scripts/rvm\" >> ~/.bashrc;
"

echo "Please type password for MySQL root account." &&
mysql -u root -p << EOF
##DROP USER '$GITLAB_USR'@'localhost';
#DROP SCHEMA \`gitlabhq_ci_production\`;
##DROP DATABASE \`gitlabhq_ci_production\`;

#CREATE USER '$GITLAB_USR'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
#SET PASSWORD FOR '$GITLAB_USR'@'localhost' = PASSWORD('$DB_PASSWORD');

CREATE DATABASE IF NOT EXISTS \`gitlab_ci_production\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;
GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON \`gitlab_ci_production\`.* TO '$GITLAB_USR'@'localhost';

FLUSH PRIVILEGES;
EOF

sudo -u $GITLAB_USR -H sh -c "
cd $GITLAB_DIR && git clone https://github.com/gitlabhq/gitlab-ci.git;
cd gitlab-ci &&
sed -e \"s/secure password/$DB_PASSWORD/g\" \
    -e \"s/username: root/username: $GITLAB_USR/g\" \
    config/database.yml.mysql > config/database.yml &&
sed -i -e \"s,/home/gitlab_ci,$GITLAB_DIR,g\" config/puma.rb &&
mkdir -p       tmp/pids tmp/sockets &&
chmod -R u+rwX tmp/pids tmp/sockets tmp log;
"

cd $GITLAB_DIR/gitlab-ci &&
sed -e "s,/home/gitlab_ci,$GITLAB_DIR,g" \
    -e "s/sudo -u gitlab_ci/sudo -u $GITLAB_USR/g; s/bash -l/bash/g" \
    -e '/STOP_SIDEKIQ="RAILS/a STOP_SIDEKIQ="$STOP_SIDEKIQ; rm -f $PID_PATH/../sockets/* $SIDEKIQ_PID"' \
    -e '/restart()/,/}/s/exit 1/start/' \
    lib/support/init.d/gitlab_ci > gitlab_ci &&
install gitlab_ci /etc/init.d/ &&
sed -e "s,/home/gitlab_ci,$GITLAB_DIR,g; s/ci.gitlab.org/$HOST_FQDN/g" \
    -e "s,location / ,location /gitlab_ci ," \
    lib/support/nginx/gitlab_ci  > gitlab_ci &&
mv gitlab_ci /etc/nginx/sites-available/ && update-rc.d gitlab_ci defaults 21

echo \"Installing gems:\" &&
gem install bundler

sudo -u $GITLAB_USR -H sh -c "
bundle --without development test &&
bundle exec whenever -w RAILS_ENV=production;
" &&
sudo -u $GITLAB_USR -H sh -c "
bundle exec rake db:setup RAILS_ENV=production
bundle exec rake db:migrate RAILS_ENV=production
"
service gitlab_ci restart && /etc/init.d/nginx restart

 # vim:sts=4:ts=8:
