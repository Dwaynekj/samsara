#!/bin/bash -e
#
# $1 - OPTIONAL
#      The name of the docker image to use.
#      ex:
#        mytest/myimage:1.0
#        some.private.docker.repo:5000/mytest/myimage:1.0
#

if [ "$(id -u)" != "0" ] ; then
    echo "Running the script with root's privileges"
    sudo "$0" "$*"
    exit $?
fi

echo "waiting for system to fully come online."
sleep 30


echo '------------------------------------------------------------------'
echo '          ephemeral  /data and /logs volumes installation'
echo '------------------------------------------------------------------'
cat > /etc/init.d/ephemeral <<\EOF
#!/bin/bash
# based on https://github.com/matthew-lucidchart/aws-ephemeral-mounts
### BEGIN INIT INFO
# Provides:          ephemeral
# Required-Start:    $syslog
# Required-Stop:     $syslog
# Should-Start:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: LVM and mount ephemeral storage
# Description:       No daemon is created or managed. This script is a Lucid
#                    creation that mounts AWS ephemeral volumes.
### END INIT INFO

VG_NAME=ephemeral

. /lib/lsb/init-functions

ephemeral_start() {
    DEVICES=$(/bin/ls /dev/xvdb* /dev/xvdc* /dev/xvdd* /dev/xvde* 2>/dev/null)
    PVSCAN_OUT=$(/sbin/pvscan)

    for device in $DEVICES; do
        if [ -z "$(/bin/echo "$PVSCAN_OUT" | grep " $device ")" ]; then
            /bin/umount "$device"
            /bin/sed -e "/$(basename $device)/d" -i /etc/fstab
            /bin/dd if=/dev/zero of="$device" bs=1M count=10
            /sbin/pvcreate "$device"
        fi
    done

    if [ ! -d "/dev/$VG_NAME" ]; then
        /sbin/vgcreate "$VG_NAME" $DEVICES
    fi

    VGSIZE=$(/sbin/vgdisplay "$VG_NAME" | grep "Total PE" | sed -e "s/[^0-9]//g")

    [ ! -e "/dev/$VG_NAME/mnt" ] && /sbin/lvcreate -l100%FREE -nmnt "$VG_NAME"

    # do mnt
    /sbin/mkfs.ext4 /dev/$VG_NAME/mnt
    /bin/mkdir -p /mnt
    [ -z "$(mount | grep " on /mnt ")" ] && rm -rf /mnt/*
    /bin/mount -t ext4 /dev/$VG_NAME/mnt /mnt
    /bin/chmod 755 /mnt

    # set up /data and /logs
    /bin/mkdir -p /mnt/data /mnt/logs
    /bin/rm -fr /data /logs
    /bin/ln -fs /mnt/data /data
    /bin/ln -fs /mnt/logs /logs
    chown -R root:logger /mnt /mnt/logs
    chmod -R g+w /mnt/logs

    log_end_msg 0
} # ephemeral_start

ephemeral_stop() {
    /bin/umount /mnt

    /sbin/vgchange -an "$VG_NAME"

    log_end_msg 0
} # ephemeral_stop


case "$1" in
  start)
        log_daemon_msg "Mounting ephemeral volumes" "ephemeral"
        ephemeral_start
        ;;

  stop)
        log_daemon_msg "Umounting ephemeral volumes" "ephemeral"
        ephemeral_stop
        ;;

  *)
        echo "Usage: /etc/init.d/ephemeral {start|stop}"
        exit 1
esac

exit 0

EOF

apt-get install -y lvm2
chown root:root /etc/init.d/ephemeral
chmod 755 /etc/init.d/ephemeral
update-rc.d ephemeral defaults 00



IMAGE=${1:-samsara/spark-worker}
echo '------------------------------------------------------------------'
echo '                    Using image:' $IMAGE
echo '------------------------------------------------------------------'
mkdir -p /etc/samsara/images
echo "$IMAGE" > /etc/samsara/images/spark-worker


echo '------------------------------------------------------------------'
echo '                    Setup upstart service'
echo '------------------------------------------------------------------'
cat >/etc/init/spark-worker.conf <<\EOF
description "Samsara Spark-worker container"
author "Bruno"
start on runlevel [2345]
stop on runlevel [016]
respawn
pre-start exec /usr/bin/docker rm spark-worker | true
script

     # wait for at least 2 master ips to come up
     while [ "$(dig +short spark-master.service.consul | wc -l)" -lt "2" ] ; do
       echo "Waiting for more spark-master.service.consul to start up... (found:$(dig +short spark-master.service.consul | wc -l))"
       sleep 3
     done

     export SPARK_MASTERS=`dig +short spark-master.service.consul | sed 's/\./-/g;s/^/ip-/g;s/$/:7077/g' | paste -s -d ','` && \

     exec /usr/bin/docker run --name spark-worker \
       --net=host \
       -p 4555:4555 \
       -p 15000:15000 \
       -v /logs/spark-worker:/logs \
       -e SPARK_MASTERS=`dig +short spark-master.service.consul | sed 's/\./-/g;s/^/ip-/g;s/$/:7077/g' | paste -s -d ','` \
       -e ADV_IP=$(curl "http://169.254.169.254/latest/meta-data/local-ipv4") \
       `cat /etc/samsara/images/spark-worker`

end script

pre-stop script
        /usr/bin/docker stop spark-worker
        /usr/bin/docker rm spark-worker
end script
EOF

echo '------------------------------------------------------------------'
echo '                Pull the latest image'
echo '------------------------------------------------------------------'
docker pull `cat /etc/samsara/images/spark-worker`


echo '------------------------------------------------------------------'
echo '                add service to consul'
echo '------------------------------------------------------------------'
cat > /etc/consul.d/spark-worker.json <<\EOF
{
  "service": {
    "name": "spark-worker",
    "tags": [],
    "port": 7078
  },
  "check": {
    "id": "spark-worker-port",
    "name": "Spark Worker port",
    "script": "/bin/nc -vz -w 1 127.0.0.1 7078",
    "interval": "5s"
  }
}
EOF
