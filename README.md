## gke-networking

### Create a service using NodePort
Set up environment
```
export REGION_NAME=us-central1
export ZONE=us-central1-a
export PROJECT_ID=$(gcloud config get project)
export CLUSTER_NAME=gke-networking
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")
```
Create a zonal cluster
```
gcloud container clusters create $CLUSTER_NAME \
--location=$ZONE
Check that the cluster is created with the default nodepool (DO NOT COPY)
```
$ kc get no
NAME                                            STATUS   ROLES    AGE     VERSION
gke-gke-networking-default-pool-d6aea2f2-l8f1   Ready    <none>   3m37s   v1.32.3-gke.1785003
gke-gke-networking-default-pool-d6aea2f2-tbnn   Ready    <none>   3m37s   v1.32.3-gke.1785003
gke-gke-networking-default-pool-d6aea2f2-vzlc   Ready    <none>   3m37s   v1.32.3-gke.1785003
```
```
Create an Nginx Deployment: This command creates a deployment named nginx-deployment that will run two replicas of the Nginx image.
```
kubectl create deployment nginx-deployment --image=nginx --replicas=2
```
Verify that the deploy pods are running on different nodes
```
$ kc get po -o wide
NAME                                READY   STATUS    RESTARTS   AGE     IP          NODE                                            NOMINATED NODE   READINESS GATES
nginx-deployment-6cfb98644c-dwlrm   1/1     Running   0          2m58s   10.52.1.5   gke-gke-networking-default-pool-d6aea2f2-tbnn   <none>           <none>
nginx-deployment-6cfb98644c-kdn2m   1/1     Running   0          2m58s   10.52.2.6   gke-gke-networking-default-pool-d6aea2f2-l8f1   <none>           <none>
```
Expose the Nginx Deployment as a NodePort Service: This command creates a service named nginx-service of type NodePort. This will make your Nginx deployment accessible on a specific port on each of your cluster nodes. Kubernetes will automatically choose a port in the default range (30000-32767).
```
kubectl expose deployment nginx-deployment --name=nginx-service --type=NodePort --port=80 --target-port=80
```
--port=80: This is the port the service will listen on within the cluster.
--target-port=80: This is the port the Nginx container is listening on inside the pod.
Verify that the service
```
$ kc get services -o wide
NAME            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE   SELECTOR
kubernetes      ClusterIP   34.118.224.1     <none>        443/TCP        11m   <none>
nginx-service   NodePort    34.118.239.252   <none>        80:32394/TCP   11s   app=nginx-deployment
```
To access your Nginx service, you'll need the external IP address of one of your GKE nodes and the NodePort assigned to the service.
1. Get the external IP of a node:
```
kubectl get nodes -o wide
```
2. Access Nginx: Open your browser and go to 
```
http://<NODE_EXTERNAL_IP>:<NODE_PORT>
```
3. If you want to make this service accessible via a public load balancer IP (which is more common for web services), you would use Type=LoadBalancer when exposing the deployment:
```
kubectl expose deployment nginx-deployment --name=nginx-lb-service --type=LoadBalancer --port=80 --target-port=80
```
Then you would get the external IP from:
```
kubectl get service nginx-lb-service
```
Output should look like this
```
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)        AGE
nginx-lb-service   LoadBalancer   34.118.232.175   34.10.185.92   80:32722/TCP   57s
```
