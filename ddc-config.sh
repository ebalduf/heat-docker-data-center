#!/usr/bin/bash
PRIVATE_IP=$(curl -fsSL http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -fsSL http://169.254.169.254/latest/meta-data/public-ipv4)
# install the NetApp Docker Volume Plugin on this node
docker plugin install store/netapp/ndvp-plugin:1.4.0 --alias netapp --grant-all-permissions
# get our docker license key from our object store
curl http://172.27.156.236:8080/v1/AUTH_7ce1fcab9a1b4b4d8dc573d5e6aa9263/Docker/license1.lic -o /root/license1.lic
# install the UCP master here
docker run --rm -i --name ucp -v /var/run/docker.sock:/var/run/docker.sock -v /root/license1.lic:/config/docker_subscription.lic docker/ucp:${UCP_version} install --host-address $PRIVATE_IP --san $PUBLIC_IP --admin-username admin --admin-password solidfire
# get the join tokens for the additional managers and workers
docker swarm join-token manager | tail -n +3 > /tmp/manager_join
docker swarm join-token worker | tail -n +3 > /tmp/worker_join
chmod 700 /tmp/manager_join /tmp/worker_join
# Configure the other masters.  This list of masters comes to use thorugh Heat
for master in `echo $the_masters | sed 's|\[||g;s|]||g;s|u'\''||g;s|'\''||g;s| ||g;s|,|\n|g' | grep -v $PUBLIC_IP`; do
  echo "Connecting DDC master node: " $master
  scp -o StrictHostKeyChecking=no /tmp/manager_join $user@$master:/tmp/manager_join
  ssh -o StrictHostKeyChecking=no $user@$master 'chmod 700 /tmp/manager_join;sudo chown root.root /tmp/manager_join;
                                                 sudo chown root.root /tmp/manager_join;
                                                 sudo bash /tmp/manager_join;
                                                 docker plugin install store/netapp/ndvp-plugin:1.4.0 --alias netapp --grant-all-permissions '
done
# Configure the nodes we have designated as DTRs. The list comes from Heat as an environment variable.
for dtr in `echo $the_DTRs | sed 's|\[||g;s|]||g;s|u'\''||g;s|'\''||g;s| ||g;s|,|\n|g'`; do
  echo "Connecting DDC DTR node: " $dtr
  scp -o StrictHostKeyChecking=no /tmp/worker_join $user@$dtr:/tmp/worker_join
  ssh -o StrictHostKeyChecking=no $user@$dtr 'chmod 700 /tmp/worker_join;sudo chown root.root /tmp/worker_join;
                                              sudo chown root.root /tmp/worker_join;
                                              sudo bash /tmp/worker_join;
                                              docker plugin install store/netapp/ndvp-plugin:1.4.0 --alias netapp --grant-all-permissions '
done
# Configure the nodes we have designated as User Nodes. The list comes from Heat as an environment variable.
for usernode in `echo $the_usernodes | sed 's|\[||g;s|]||g;s|u'\''||g;s|'\''||g;s| ||g;s|,|\n|g'`; do
  echo "Connecting DDC User node: " $usernode
  scp -o StrictHostKeyChecking=no /tmp/worker_join $user@$usernode:/tmp/worker_join
  ssh -o StrictHostKeyChecking=no $user@$usernode 'chmod 700 /tmp/worker_join;sudo chown root.root /tmp/worker_join;
                                                   sudo chown root.root /tmp/worker_join;
                                                   sudo bash /tmp/worker_join;
                                                   docker plugin install store/netapp/ndvp-plugin:1.4.0 --alias netapp --grant-all-permissions '
done
# Create a 12 digit randome replica ID
REPLICA_ID=$(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 12)
# seems like we need to wait a bit for things to be ready.
sleep 20
# Install the primary DTR node. 
DTR_MASTER=$(echo $DTRnode_names | sed 's|\[||g;s|]||g;s|u'\''||g;s|'\''||g;s| ||g;s|,|\n|g' | head -1)
docker run --rm docker/dtr:${DTR_version} install --dtr-external-url https://$DTR_MASTER.pm.solidfire.net --ucp-node $DTR_MASTER.pm.solidfire.net -ucp-username admin --ucp-password solidfire --ucp-insecure-tls --ucp-url https://$(hostname) --replica-id ${REPLICA_ID}
# Join (not install) the other DTRs to the main DTR via the replica ID. 
for dtrn in `echo $DTRnode_names | sed 's|\[||g;s|]||g;s|u'\''||g;s|'\''||g;s| ||g;s|,|\n|g' | tail -n +2`; do
  echo "Installing DTR on node: " $dtrn
  docker run --rm docker/dtr:${DTR_version} join --ucp-node $dtrn.pm.solidfire.net -ucp-username admin --ucp-password solidfire --ucp-insecure-tls --ucp-url https://$(hostname) --existing-replica-id ${REPLICA_ID}
done
