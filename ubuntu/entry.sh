#!/bin/bash
echo "#================================================================================================================"
echo "Starting Swarm setup"
echo "NODE_TYPE=$NODE_TYPE"
echo "DYNAMODB_TABLE=$DYNAMODB_TABLE"
echo "AWS_REGION=$REGION"

function get_region {
    export AZ=$(wget -O - http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null)
    export REGION=${AZ::-1}
    echo "Availability Zone=$AZ and AWS_REGION=$REGION"
}

get_primary_manager_ip()
{
    # query dynamodb and get the Ip for the primary manager.
    MANAGER=$(aws dynamodb get-item --region $REGION --table-name $DYNAMODB_TABLE --key '{"node_type":{"S": "primary_manager"}}')
    export MANAGER_IP=$(echo $MANAGER | jq -r '.Item.ip.S')
    export MANAGER_TOKEN=$(echo $MANAGER | jq -r '.Item.manager_token.S')
    export WORKER_TOKEN=$(echo $MANAGER | jq -r '.Item.worker_token.S')

    echo "PRIMARY_MANAGER_IP=$MANAGER_IP"
    echo "MANAGER_TOKEN=$MANAGER_TOKEN"
    echo "WORKER_TOKEN=$WORKER_TOKEN"
}

get_tokens()
{
    export MANAGER_TOKEN=$(docker swarm join-token manager -q)
    export WORKER_TOKEN=$(docker swarm join-token worker -q)

    echo "MANAGER_TOKEN=$MANAGER_TOKEN from cluster"
    echo "WORKER_TOKEN=$WORKER_TOKEN from cluster"
}

confirm_primary_ready()
{
    n=0
    until [ $n -ge 5 ]
    do
        get_primary_manager_ip
        # if Manager IP or manager_token is empty or manager_token is null, not ready yet.
        # token would be null for a short time between swarm init, and the time the
        # token is added to dynamodb
        if [ -z "$MANAGER_IP" ] || [ -z "$MANAGER_TOKEN" ] || [ "$MANAGER_TOKEN" == "null" ]; then
            echo "Primary manager Not ready yet, sleep for 60 seconds."
            sleep 60
            n=$[$n+1]
        else
            echo "Primary manager is ready."
            break
        fi
    done
}

join_as_secondary_manager()
{
    echo "Setting up Secondary Manager"

    if [ -z "$MANAGER_IP" ] || [ -z "$MANAGER_TOKEN" ] || [ "$MANAGER_TOKEN" == "null" ]; then
        confirm_primary_ready
    fi

    # sleep for 30 seconds to make sure the primary manager has enough time to setup before join
    sleep 30

    docker swarm join --token $MANAGER_TOKEN --listen-addr $PRIVATE_IP:2377 --advertise-addr $PRIVATE_IP:2377 $MANAGER_IP:2377
}

setup_manager()
{
    echo "Setting up a Manager"

    export PRIVATE_IP=`wget -qO- http://169.254.169.254/latest/meta-data/local-ipv4`

    echo "PRIVATE_IP=$PRIVATE_IP"
    echo "PRIMARY_MANAGER_IP=$MANAGER_IP"

    if [ -z "$MANAGER_IP" ]; then
        echo "Primary Manager IP is not set yet, lets try and set it."
        # try to write to the table as the primary_manager, if it succeeds then it is the first
        # and it is the primary manager. If it fails, then it isn't first, and treat the record
        # that is there, as the primary manager, and join that swarm.
        aws dynamodb put-item \
            --table-name $DYNAMODB_TABLE \
            --region $REGION \
            --item '{"node_type":{"S": "primary_manager"},"ip": {"S":"'"$PRIVATE_IP"'"}}' \
            --condition-expression 'attribute_not_exists(node_type)' \
            --return-consumed-capacity TOTAL
        PRIMARY_RESULT=$?
        echo "PRIMARY_RESULT=$PRIMARY_RESULT"

        if [ $PRIMARY_RESULT -eq 0 ]; then
            echo "Setting up Primary Manager"
            # we are the primary, so init the cluster
            docker swarm init --listen-addr $PRIVATE_IP:2377 --advertise-addr $PRIVATE_IP:2377
            # we can now get the tokens.
            get_tokens

            # update dynamodb with the tokens
            aws dynamodb put-item \
                --table-name $DYNAMODB_TABLE \
                --region $REGION \
                --item '{"node_type":{"S": "primary_manager"},"ip": {"S":"'"$PRIVATE_IP"'"},"manager_token": {"S":"'"$MANAGER_TOKEN"'"},"worker_token": {"S":"'"$WORKER_TOKEN"'"}}' \
                --return-consumed-capacity TOTAL
        else
            echo "Seems like another node took the primary manager spot so join as Secondary Manager"
            join_as_secondary_manager
        fi
    else
        join_as_secondary_manager
    fi
}

setup_worker()
{
    echo " Setting up worker node"

    if [ -z "$MANAGER_IP" ] || [ -z "$WORKER_TOKEN" ] || [ "$MANAGER_TOKEN" == "null" ]; then
        confirm_primary_ready
    fi

    # sleep for 30 seconds to make sure the primary manager has enough time to setup before join
    sleep 30

    docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377
}

if [ -z "$REGION" ]; then
    get_region
fi

# see if the primary manager IP is already set.
get_primary_manager_ip

if [ "$NODE_TYPE" == "manager" ] ; then
    setup_manager
elif [ "$NODE_TYPE" == "worker" ] ; then
    setup_worker
else
    echo " It is neither a Manager nor Worker so not doing anything!"
fi

echo "Completed Swarm setup"
echo "#================================================================================================================"
