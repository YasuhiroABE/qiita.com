---
title: Synologyで稼動していたGitlabの引越し作業
tags:
  - GitLab
  - synology
  - DSM
private: false
updated_at: '2024-02-16T09:34:59+09:00'
id: eaccfe6c00b699cf8df1
organization_url_name: null
slide: false
ignorePublish: false
---
# はじめに

新しいSynology NASのOSであるDSM7から、Gitlabパッケージがサポートされなくなったので、かなりのプロジェクトが登録されているGitlabインスタンスのバックアップを取得して、Ubuntu上のDockerイメージに引っ越しをした時のメモです。

Gitlabさえ必要なくなれば、そのままDSM 7にバージョンアップする予定です。

# 環境

DS916+上のGitlabから、一般的なUbuntu環境に移行しました。

## 引越し元 (Synology NAS)

* ホスト名: ds916p
* 利用者ID: yasu
* Synology NAS: DS916+ 
* DSM Version: DSM 6.2.4-25556 Update 2
* Gitlabパッケージ: 13.12.2
* /home/git/data領域の保存先: /volume1/docker/gitlab/gitlab/

## 引越し先 

* Ubuntu 20.04 LTS (x86_64版)
* Docker CE

# 参考資料

* [Synology GitLab Backup and Restore](https://blog.stead.id.au/2018/01/synology-gitlab-backup-and-restore.html)
* [Back up and restore GitLab (all-tiers self-managed)](https://docs.gitlab.com/ee/raketasks/backup_restore.html)
* [GitHub - sameersbn/docker-gitlab](https://github.com/sameersbn/docker-gitlab)


# 事前調査

作業のため、あらかじめ DS916+ でSSH経由でのログインを許可しておき、別システムからSSH経由でログインします。
個人的に利用している環境なので、管理用と一般ユーザーでIDは分けておらず、IDは1つだけ(yasu)しか利用していません。

```bash:ssh経由でのログインし、root権限を取得できることを確認する
$ ssh -x -o PreferredAuthentications=password yasu@ds916p
yasu@ds916p:/$ sudo id
Password: 
uid=0(root) gid=0(root) groups=0(root),2(daemon),19(log)
```

sudo を利用して、root権限でコマンドを実行することができることを確認して、Gitlabの状況を確認します。

## Synology上のGitlabが稼動するDocker環境の確認

まずコンテナの名前などを確認していきます。

```bash:
yasu@ds916p:/$ sudo docker ps
CONTAINER ID   IMAGE                              COMMAND                  CREATED         STATUS      PORTS                                                   NAMES
697bd20839fb   sameersbn/gitlab:13.12.2           "/sbin/entrypoint.sh…"   2 months ago    Up 5 days   443/tcp, 0.0.0.0:30001->22/tcp, 0.0.0.0:30000->80/tcp   synology_gitlab
870bc9e286f6   sameersbn/postgresql:12-20200524   "/sbin/entrypoint.sh"    2 months ago    Up 5 days   5432/tcp                                                synology_gitlab_postgresql
919eacf16efe   sameersbn/redis:4.0.9-1            "/sbin/entrypoint.sh"    2 months ago    Up 5 days   6379/tcp                                                synology_gitlab_redis
```

次にsynology_gitlabインスタンスの設定などを確認します。

```bash:
yasu@ds916p:/$ sudo docker exec -it synology_gitlab bash
root@synology_gitlab:/home/git/gitlab# 
```

ここからはdocker内部で設定状況などを確認しつつ、バックアップファイルの取得を目指します。
まず、バックアップ関連の設定を抜粋すると次のようになっています。

```yaml:config/gitlab.yml
  ## Backup settings                                                                                                                                                                                                             
  backup:                                                                                                                                                                                                                        
    path: "/home/git/data/backups"   # Relative paths are relative to Rails.root (default: tmp/backups/)                                                                                                                         
    archive_permissions: 0600 # Permissions for the resulting backup.tar file (default: 0600)                                                                                                                                    
    keep_time: 0   # default: 0 (forever) (in seconds)                                                                                                                                                                           
    pg_schema:      # default: nil, it means that all schemas will be backed up                                                                                                                                                  
    upload:                                                                                                                                                                                                                      
      # Fog storage connection settings, see http://fog.io/storage/ .     
```

現時点では、``/home/git/data/backups`` にはまだファイルは存在していません。
とりあえず公式ガイドに従って、``gitlab-backup``コマンドを実行してみます。

```bash:gitlab-backupコマンドの動作確認
root@synology_gitlab:/home/git/gitlab# type gitlab-backup
bash: type: gitlab-backup: not found
```

PATH環境変数から検索できる場所にはgitlab-backupコマンドは存在していないようでした。

直接rakeコマンドを実行するために設定ファイルを確認しておきます。

```bash:rakeファイルの確認
root@synology_gitlab:/home/git/gitlab# more lib/tasks/gitlab/backup.rake 
```

リストアもある程度は自動的に対応してくれそうな雰囲気でした。

次にdfコマンドで/home/git/dataの領域がどこに存在するのか確認しておきます。

```bash:dfコマンドの実行
root@synology_gitlab:/home/git/gitlab# df -m /home/git/data/backups
Filesystem     1M-blocks     Used Available Use% Mounted on
/dev/vg1000/lv  21963334 11123090  10840244  51% /home/git/data
```
どうもマウントしているボリュームはNASで共有している書き込み可能な領域全体を指しているようです。
実際のデータ使用量を確認しておきます。

```bash:duコマンドの実行
root@synology_gitlab:/home/git/gitlab# du -ms /home/git/data/       
1508    /home/git/data/
```

この程度だと様々な制限にひっかかる可能性はなさそうなので、時間はかからずに作業が進められそうです。

# 作業の開始

だいたい状況が分かったので公式ガイドを参考にしながら作業を進めていきます。

## バックアップの取得

まずdockerコンテナ上でバックアップを取得します。公式ガイドのソースコードから導入した場合の手順を参考にします。

```bash:rakeコマンドによるバックアップの取得
root@synology_gitlab:/home/git/gitlab# sudo -u git -H bundle exec rake gitlab:backup:create RAILS_ENV=production                                            
2021-09-15 04:13:27 +0000 -- Dumping database ...                                                                                      
Dumping PostgreSQL database gitlab ... [DONE]                                                                                                            
2021-09-15 04:13:41 +0000 -- done                                                                                                         
2021-09-15 04:13:41 +0000 -- Dumping repositories ...                                                                                                       
 * yasu/ansible-setup-opm001 (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b) ...                         
 * yasu/ansible-setup-opm001 (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b) ... [DONE]                                    
 * yasu/ansible-setup-opm001.wiki (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b.wiki) ...           
 * yasu/ansible-setup-opm001.wiki (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b.wiki) ... [EMPTY] [SKIPPED]           
 * yasu/ansible-setup-opm001.design (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b.design) ...
 * yasu/ansible-setup-opm001.design (@hashed/6b/86/6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b.design) ... [EMPTY] [SKIPPED]
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping uploads ... 
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping builds ... 
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping artifacts ... 
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping pages ... 
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping lfs objects ... 
2021-09-15 04:15:02 +0000 -- done
2021-09-15 04:15:02 +0000 -- Dumping container registry images ... 
2021-09-15 04:15:02 +0000 -- [DISABLED]
Creating backup archive: 1631679302_2021_09_15_13.12.2_gitlab_backup.tar ... done
Uploading backup archive to remote storage  ... skipped
Deleting tmp directories ... done
done
done
done
done
done
done
done
Deleting old backups ... skipping
Warning: Your gitlab.rb and gitlab-secrets.json files contain sensitive data 
and are not included in this backup. You will need these files to restore a backup.
Please back them up manually.
Backup task is done.
```

最後の部分で、gitlab.rb と gitlab-secrets.json ファイルの2つがバックアップに含まれていないと警告されていますが、公式ガイドでは実際には /home/git/gitlab/config/ 以下に異なる名前で配置されていることが分かります。

今回はこの領域はdockerコンテナに含まれるため起動のたびに初期化されるため、ここには依存しない形(主に環境変数)でシステムが稼動しています。

そのため、ここでのバックアップは、tarファイルだけを取り扱います。

## バックアップファイルの転送

使用している環境では、gitlabコンテナでマウントしている/ home/git/data は /volume1/docker/gitlab/gitlab/ にマッピングされています。転送先のシステムから、sftpコマンドで必要なファイルをバックアップします。

sftpで接続すると、/voluem1/ を / とする環境に入りますので、必要なファイルを取得します。

```bash:sftpコマンドによるバックアップファイルの転送
$ sftp yasu@ds916p
...
sftp> pwd
Remote working directory: /

sftp> get docker/gitlab/gitlab/backups/*
Fetching /docker/gitlab/gitlab/backups/1631679302_2021_09_15_13.12.2_gitlab_backup.tar to 1631679302_2021_09_15_13.12.2_gitlab_backup.tar
/docker/gitlab/gitlab/backups/1631679302_2021_09_15_13.12.2_gitlab_backup.tar       100% 1493MB  49.0MB/s   00:30    
```

ここまでで、とりあえず必要なファイルの取得には成功しました。

## sameersbn/gitlab の作者によるバックアップの取得方法について

参考情報にも挙げている作者のページには、バックアップとリストアについて掲載されています。

* [sameersbn/gitlab - Creating backups](https://github.com/sameersbn/docker-gitlab#creating-backups)

この中で作者はバックアップの取得についてrunning状態では取得しないように警告しています。
とはいえ、synologyの環境ではGitlabを停止するとPostgreSQLやRedisを含めて停止するため、そのまま実行できそうにはありません。

まずは先の方法で取得したバックアップからリストア可能か確認することにします。

# 引越し先のマシンでの設定作業

ここから先の作業は、先ほどsftpコマンドを実行した引越し先のホストで行なっていきます。

## Gitlabの起動

引越し先のホストではdocker-composeを利用して、待ち受け用のgitlabインスタンスを実行します。

```bash:docker-composeによる起動
## 適当なディレクトリへ移動
$ mkdir -p ~/sameersbn-gitlab
$ cd ~/sameersbn-gitlab

## docker-compose.yml ファイルの取得
$ wget https://raw.githubusercontent.com/sameersbn/docker-gitlab/master/docker-compose.yml

## gitlabのバージョンをSynologyと合わせる。(14.2.3 → 13.12.2)
$ sed -i.bak -e 's!sameersbn/gitlab:.*$!sameersbn/gitlab:13.12.2!' docker-compose.yml

## firefox, chromiumなどでは10080ポートに接続ができないので変更する
$ sed -i.bak -e 's!10080:80!80:80!' docker-compose.yml

## 合わせてGITLAB_HOST, GITLAB_PORTを変更します。
$ sed -i.bak -e 's!GITLAB_HOST=.*$!GITLAB_HOST=example.com!' docker-compose.yml
$ sed -i.bak -e 's!GITLAB_PORT=.*$!GITLAB_PORT=80!' docker-compose.yml

## DB接続時のパスワードを適当な乱数に変更します。
$ sed -i.bak -e "s/DB_PASS=.*$/DB_PASS=$(openssl rand -hex 8)/" docker-compose.yml

## Gitlabの起動
$ sudo docker-compose up
```

dockerコマンドで起動したコンテナの名前などを確認しておきます。

```bash:docker-psコマンドの出力
yasu@desktop:~/docker/gitlab$ sudo docker ps 
CONTAINER ID   IMAGE                                                  COMMAND                  CREATED              STATUS                                 PORTS                                                                 
                 NAMES
6bc66ea4cb36   sameersbn/gitlab:13.12.2                               "/sbin/entrypoint.sh…"   About a minute ago   Up About a minute (health: starting)   0.0.0.0:80->80/tcp, :::80->80/tcp, 443/tcp, 0.0.0.0:10022->22/tcp, :::10022->22/tcp    gitlab_gitlab_1
410d21e8d667   redis:6.2                                              "docker-entrypoint.s…"   About a minute ago  Up About a minute                      6379/tcp                                                                                gitlab_redis_1
e83e71e09977   sameersbn/postgresql:12-20200524                       "/sbin/entrypoint.sh"    About a minute ago   Up About a minute                      5432/tcp                                                                               gitlab_postgresql_1
```

素の状態でdocker-composeを実行すると、コンテナ内で/home/git/dataにマウントされているディレクトリが分かりにくくなります。
まずはバックアップファイルを配置するためのディレクトリを確認します。

```bash:volumeの状態を確認する
$ sudo docker inspect gitlab_gitlab_1 | grep _data
                "Source": "/var/lib/docker/volumes/gitlab_gitlab-data/_data",
```

/var/lib/docker/volumes/gitlab_gitlab-data/_data に必要なファイルをコピーします。

```bash:sftpで取得したファイルのコピー
$ sudo cp *.tar /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups/

$ sudo ls -l /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups/
-rw------- 1 root root 1565429760 Sep 15 15:20 1631679302_2021_09_15_13.12.2_gitlab_backup.tar

## コンテナ内部ではgitユーザーでコマンドを実行するため、パーミッションを出しておきます。
$ sudo chmod 0644 /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups/1631679302_2021_09_15_13.12.2_gitlab_backup.tar
```

リストアコマンドを実行します。

```bash:docker-composeを利用したリストア
## あらかじめgitlabを停止させます。必要に応じて別のターミナルから実行します
$ cd ~/sameersbn-gitlab
$ sudo docker-compose down

$ sudo docker-compose run --rm gitlab app:rake gitlab:backup:restore
Starting gitlab_postgresql_1 ... done
Starting gitlab_redis_1      ... done
...
gitlab_extensions:sshd: stopped
gitlab_extensions:cron: stopped
gitlab:gitlab-workhorse: stopped
gitlab:puma: stopped

‣ 1631679302_2021_09_15_13.12.2_gitlab_backup.tar (created at 15 Sep, 2021 - 09:45:02 IST)

Select a backup to restore: 1631679302_2021_09_15_13.12.2_gitlab_backup.tar
Running raketask gitlab:backup:restore...
Unpacking backup ... done
Be sure to stop Puma, Sidekiq, and any other process that
connects to the database before proceeding. For Omnibus
installs, see the following link for more information:
https://docs.gitlab.com/ee/raketasks/backup_restore.html#restore-for-omnibus-gitlab-installations

Before restoring the database, we will remove all existing
tables to avoid future upgrade problems. Be aware that if you have
custom tables in the GitLab database these tables and all data will be
removed.

Do you want to continue (yes/no)? yes

...
2021-09-15 12:01:10 +0530 -- Restoring lfs objects ... 
2021-09-15 12:01:10 +0530 -- done
This task will now rebuild the authorized_keys file.
You will lose any data stored in the authorized_keys file.
Do you want to continue (yes/no)? yes

Warning: Your gitlab.rb and gitlab-secrets.json files contain sensitive data 
and are not included in this backup. You will need to restore these files manually.
Restore task is done.
```

私の環境では、およそ2分ほどで作業が終わりました。
"Restore task is done."のメッセージを確認し、この状態でdockerを起動し、動作を確認します。

```bash:GitLabの起動
$ sudo docker-compose up
```

## 最新バージョンへの変更

おおよそ正しく動いたことが確認できたタイミングで、13.12.2に書き換えたコンテナのタグ(バージョン)を、最新版(14.2.3)に変更しておきます。

ただし、いきなり14.2.3に上げた時には次のようなメッセージが出力され、正常に稼動しませんでした。

```text:docker-composeでの起動後に出力されたエラーメッセージの抜粋
Missing Rails.application.secrets.openid_connect_signing_key for production environment. The secret will be generated and stored in config/secrets.yml.                                                          
gitlab_1      | rake aborted!                                                                                                                                                                                                    
gitlab_1      | StandardError: An error has occurred, all later migrations canceled:                                                                                                                                             
gitlab_1      |                                                                                                                                                                                                                  
gitlab_1      | Expected batched background migration for the given configuration to be marked as 'finished', but it is 'active':       {:job_class_name=>"CopyColumnUsingBackgroundMigrationJob", :table_name=>"ci_stages", :column_name=>"id", :job_arguments=>[["id"], ["id_convert_to_bigint"]]}                                                                                                                                                              
gitlab_1      |                                                                                                                                                                                                                  
gitlab_1      | Finalize it manualy by running                                                                                                                                                                                   
gitlab_1      |                                                                                                                                                                                                                  
gitlab_1      |         sudo gitlab-rake gitlab:background_migrations:finalize[CopyColumnUsingBackgroundMigrationJob,ci_stages,id,'[["id"]\, ["id_convert_to_bigint"]]']                                                         
gitlab_1      |                                                                                                                                                                                                                  
gitlab_1      | For more information, check the documentation                                                                                                                                                                    
gitlab_1      |                                                                                                                                                                                                                  
gitlab_1      |         https://docs.gitlab.com/ee/user/admin_area/monitoring/background_migrations.html#database-migrations-failing-because-of-batched-background-migration-not-finished   
```

>【2024/2/16追記】[GitLabの公式ドキュメント](https://docs.gitlab.com/ee/update/#upgrade-paths)を参照すると、13.12.2から14系列の最新にするアップグレードパスは、**14.0.12 > 14.3.6 > 14.9.5 > 14.10.5** となっています。以下では14.1.0を経由していますが、v13の最新版を経由してこの公式サイトに掲載されている順番でアップグレードしてください。

このメッセージに含まれるWebページを確認すると、14.1.xにして該当のジョブが終了するまで待つか、コマンドを入力してステータスを変更しろとあるので次のように、一度14.1.0を経由して、最新版の14.2.3に更新しました。

```bash:バージョンアップ作業の概要
## コンテナの停止
$ sudo docker-compose down

## docker-compose.ymlファイルの編集
$ sed -i.bak -e 's!sameersbn/gitlab:.*$!sameersbn/gitlab:14.1.0!' docker-compose.yml

## コンテナの起動
$ sudo docker-compose up

## Webブラウザから、rootユーザーでログインし、Admin → Monitoring → Background Migrations に進み、ジョブの完了を待つ (約20分)

## バージョンを14.2.x以降に変更し、再度停止、起動する。
$ sed -i.bak -e 's!sameersbn/gitlab:.*$!sameersbn/gitlab:14.2.3!' docker-compose.yml
$ sudo docker-compose down
$ sudo docker-compose up -d
```

最後の'-d'オプションで、バックグラウンドで起動します。
以上で作業は完了です。

## その他の設定について

### Web UI接続のためのポート番号の変更

SSHサーバーへの接続をSynologyでのGitlabと同様に 30001 に変更したいという場合には、ports設定の他に、GITLAB_SSH_PORTのような環境変数も合わせて変更する必要があります。

### タイムゾーンの変更

デフォルトの docker-compose.yml ファイルでは、Asia/Kolkata (+5:30) が設定されているので、Asia/Tokyoに変更しておきます。

### 既存リポジトリの設定変更

Synology NASでは、SSH経由でのアクセスに30001番ポートを利用していました。
これが10022などに変更されているため、既存のリポジトリは、~/.git/config ファイルを変更し、url = 行を変更する必要があります。

## 既に配置している作業用リポジトリの設定変更

作業用に特定のディレクトリに、このGitLabを利用するディレクトリが存在しています。
一括して変更した際の作業ログを残しておきます。

### .git/config ファイルの変更

一括で設定を変更するために次のようなワンライナーを実行しています。

"ds916p.example.com"が元のホスト名、"mygitlab.example.com"が移行先のホスト名です。

```bash:一括変更した時のワンライナー
$ find . -type f -path "*/.git/config" | while read file ; do sed -i.bak.$(date +'%Y%m%d.%H%M%S') -e '/url/s/ds916p.example.com/mygitlab.example.com/' -e '/url/s/:30001/:10022/' $file ; done  
```

## バックアップの定期的な取得

Synologyの場合はシステムの機能でバックアップを取得していました。
今回利用した sameersbn/docker-gitlab は、Synologyと同じDockerイメージですが、デフォルトで日毎のバックアップ取得が設定されています。

```yaml:docker-compose.ymlからの抜粋
    - GITLAB_BACKUP_SCHEDULE=daily
    - GITLAB_BACKUP_TIME=01:00
```

docker-composeが準備した領域をみると、翌日にはバックアップが午前1時に取得されていました。

```bash:バックアップの取得状況
$ sudo ls -ltr /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups
total 3057632
-rw-r--r-- 1 root root 1565429760 Sep 15 17:59 1631679302_2021_09_15_13.12.2_gitlab_backup.tar
drwx------ 7 yasu yasu       4096 Sep 15 18:10 tmp
-rw------- 1 yasu yasu 1565573120 Sep 16 01:00 1631721635_2021_09_16_14.2.3_gitlab_backup.tar

$ sudo ls -ltr /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups/tmp/
total 20
drwx------ 2 yasu yasu 4096 Sep 15 18:10 uploads.1631697033
drwx------ 2 yasu yasu 4096 Sep 15 18:10 builds.1631697033
drwx------ 2 yasu yasu 4096 Sep 15 18:10 artifacts.1631697033
drwx------ 2 yasu yasu 4096 Sep 15 18:10 pages.1631697033
drwx------ 2 yasu yasu 4096 Sep 15 18:10 lfs.1631697033
```

# docker-compose.yml ファイルの差分

全体の差分は以下のようになっています。

```diff:
--- docker-compose.yml.orig     2021-09-16 16:05:07.141632691 +0900
+++ docker-compose.yml  2021-09-15 18:33:24.244059280 +0900
@@ -16,7 +16,7 @@             
     - postgresql-data:/var/lib/postgresql:Z
     environment:           
     - DB_USER=gitlab
-    - DB_PASS=password  
+    - DB_PASS=774bc0d5d4dd3545
     - DB_NAME=gitlabhq_production
     - DB_EXTENSION=pg_trgm,btree_gist
                        
@@ -27,7 +27,7 @@                            
     - redis         
     - postgresql           
     ports:                     
-    - "10080:80"                                                    
+    - "80:80"               
     - "10022:22"                                                                
     volumes:                                           
     - gitlab-data:/home/git/data:Z                                                           
@@ -44,20 +44,20 @@                                                                                 
     - DB_HOST=postgresql                                                                          
     - DB_PORT=5432
     - DB_USER=gitlab                                                                         
-    - DB_PASS=password                           
+    - DB_PASS=774bc0d5d4dd3545                                                             
     - DB_NAME=gitlabhq_production                                                                      
        
     - REDIS_HOST=redis                                    
     - REDIS_PORT=6379                                    
                                                             
-    - TZ=Asia/Kolkata                                   
-    - GITLAB_TIMEZONE=Kolkata                         
+    - TZ=Asia/Tokyo         
+    - GITLAB_TIMEZONE=Tokyo

     - GITLAB_HTTPS=false
     - SSL_SELF_SIGNED=false

-    - GITLAB_HOST=localhost
-    - GITLAB_PORT=10080
+    - GITLAB_HOST=mygitlab.example.com
+    - GITLAB_PORT=80
     - GITLAB_SSH_PORT=10022
     - GITLAB_RELATIVE_URL_ROOT=
     - GITLAB_SECRETS_DB_KEY_BASE=long-and-random-alphanumeric-string
```

# まとめ

Synology NASのパッケージとして配布されていたGitlabであれば、事前に確認し、更新ミスなどが発生しにくいだろうと考えて利用していました。
実際にSynology NASはめったに停止しないため、この上で動作するサービスはとても便利でした。

今回は、とりあえずXubuntu Desktopとして利用している環境に引越しをしたので、以前よりは頻繁に再起動などが発生しそうです。
最終的には、Kubernetesクラスターに引越しすることを想定する必要がありそうです。

Gitlab公式のOperatorはOpenShift環境での稼動を前提としているようだったので、躊躇していました。
今回利用した sameersbn/docker-gitlab の環境はとても便利そうで、Kubernetesに対応した設定ファイルも含まれているので、docker-compose.ymlファイルを確認しても、簡単にk8s環境で動かすことができそうです。

Synology NASに入って、詳細に設定ファイルなどを確認しましたが、データベースへの接続に利用しているID,パスワードがデフォルトのままだったり、致命的ではないものの本格的に利用するためには修正した方が良い設定が発見できました。

GitLabインスタンスの引越しは、稼動確認が十分に行なえないので、できれば避けたいところです。
いくつかのサンプルを抽出し、.git/config ファイルの url = 行を変更し、問題なく動くことを確認しました。

# その後 - Docker Desktop環境への移行

ユーザー環境が多様になりamd64なホストOS上でもARM版のコンテナ・イメージもbuildする必要が出てきました。このため、docker-ce-cli環境から、docker-desktop環境へ移行しました。

いままではホストOS上の/var/lib/dockerをみていれば良かったのですが、docker-desktopではdockerのホストOSがQEMUのVMへ変更されているため、docker-desktop版ではいままでのvolumesを引き継ぐことができませんし、gitlabのバックアップイメージも直接コピーすることができません。

微妙な違いを除けば、基本的には、ここに書いた手順でリストアは完了しましたが、今後はgitlabのバックアップイメージがVM上に保存されることになるため、docker cpなどで定期的に取り出して、NASなどにバックアップすることが必要になります。

ちょうど良い機会だったので、バックアップイメージを/var/lib/docker以下にcpしていた部分は、docker cpコマンドで置き換えるなどの変更を反映させたログを残しておくことにします。

docker-compose.ymlファイルは同一ホストなので、そのまま残っています。

## Docker-Desktopの導入

docker-desktopの導入は公式ガイドに従って実施する必要があります。またdocker-composeコマンドは削除する必要があります。

```bash:準備作業
## kvmグループに自身を追加するなど、公式ガイドに従って手順を実行していく
$ sudo apt-get install ./Downloads/docker-desktop-4.10.1-amd64.deb 
$ sudo rm /usr/local/bin/docker-compose
$ sudo apt install docker-compose-plugin
```

systemctl管理下にあるdocker.serviceなどはmaskされ、起動することはできなくなりますが、/var/lib/dockerが消えるわけではないので心配するほどではないかなと思います。

それでも、いろいろdockerコマンドが動かなくなるなど、問題が発生して、一度は、docker-ce-cilパッケージをdocker-desktopは残したまま再インストールしたり、いつの間にかuninstallされていた、docker-desktopを再導入したりと、問題は発生しています。

## リストアの実行

docker-desktopではcompose-pluginを利用しているので、docker-composeコマンドの代りに、docker composeを使用しています。

```bash:dockerコマンドからcompose命令の利用
$ ls
docker-compose.yml
$ docker compose up
... 
```

起動したら、/var/lib/以下のファイルをcpします。

```bash:バックアップファイルのコンテナ内部へのコピー
## コンテナ名(NAME)を指定して/home/git/data/backupsにファイルをコピーする
$ docker cp /var/lib/docker/volumes/gitlab_gitlab-data/_data/backups/1658678452_2022_07_25_14.2.3_gitlab_backup.tar gitlab-gitlab-1:/home/git/data/backups/
```

↑で指定するtarファイルは存在するものに変更してください。

ここからリストアするコマンドは、ほぼ同一です。

```bash:停止とリストア
$ docker compose down
$ docker compose run --rm gitlab app:rake gitlab:backup:restore
```

リストアタスクの中では、どのtarファイルから復元するか、間違いを避けるためにtarファイルを削除して良いか、などの質問がありますが、基本的にファイル名や'yes'を回答して進めていきます。

## バックアップファイルの扱い

新しくdocker-desktop環境内でgitlabが動作するようになると、次に問題になるのは、バックアップファイルの保存です。また似たような状況になった時のために、gitlabのバックアップは定期的に取得するだけでなく、安全な場所に保存することが必要です。

実際には次のようなスクリプトで最新の2つだけを取得するようにしています。

```bash:backup-docker-gitlab.sh
#!/bin/bash 

DOCKER_GITLAB_NAME="gitlab-gitlab-1"
DOCKER_GITLAB_BACKUP_DIRPATH="/home/git/data/backups"

BACKUP_DEST_DIR="/backup/gitlab"

docker exec -it "${DOCKER_GITLAB_NAME}" ls ${DOCKER_GITLAB_BACKUP_DIRPATH} | grep _gitlab_backup.tar | sort -n | tail -2 | sed
 -e 's/\r//g' | while read backup
do
    docker cp "${DOCKER_GITLAB_NAME}:${DOCKER_GITLAB_BACKUP_DIRPATH}/${backup}" "${BACKUP_DEST_DIR}"
done
```

バックアップファイルの数は、また別のスクリプトで定期的に削除しています。

以上
