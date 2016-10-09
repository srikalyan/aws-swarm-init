# aws-swarm-init
Docker image responsible for automatic initialization (setup) of docker swarm cluster. Most of the logic lives in the 
script `entry.sh`.

In order to setup a swarm cluster, 

1. `swarm init` must be run on one of the  managers 
2. `swarm join` on remaining nodes (both managers and workers) with appropriate tokens
 
To perform the same steps automatically, dynamodb's locking feature would be used. Due to locks, only one manager is 
capable of querying/inserting data into dynamodb and a manager which is successfully queries/inserts into dynamodb 
would perform `swarm init` and other utilize the data in the dynamodb for joining the cluster.

This docker image needs following environment variables

  - `NODE_TYPE`: Should be either `manager` or `worker`
  - `DYNAMODB_TABLE`: Name of the dynamodb table to be used for locking and passing cluster information
  - `REGION`: AWS region in which dynamodb table was created (if not provided will default to region of the instance)


## docker-compose:

    version: "2"
    services:
        init-aws:
          image: "srikalyan/aws-swarm-init:<version>"
          container_name: "aws-swarm-init"
          restart: "no"
          environment:
            NODE_TYPE: "<manager|worker>"
            DYNAMODB_TABLE: "<dynamodb_table>"
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            -  /usr/bin/docker:/usr/bin/docker
            - /var/log:/var/log


*Note 1*: entry.sh is mostly taken from the docker for aws with few modifications 

*Note 2*: This image needs a docker client but does not install one as this would create unnecessary versions which we 
could easily skip by mount the docker binary from host ubuntu machine.

*Note 3*: If you need to delete **all** the manager nodes then clear out your dynamodb table before destroying your 
manager nodes.
