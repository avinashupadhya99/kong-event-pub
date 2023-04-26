# Important notes: This script assumes you have env vars SASL_USER, SASL_PASSWORD BOOTSTRAP_SERVERS, TOPIC set.
# It is also assumed that the topic itself exists
import requests
import os
import json
from datetime import datetime
from confluent_kafka import Consumer, TopicPartition, KafkaError
import time

def make_order_request():
    url = "http://kong:8000/order"
    headers = {"Content-Type": "application/json"}
    payload = {"foo": "bar", "time": datetime.now().isoformat()}
    try:
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
    except requests.exceptions.HTTPError as err:
        print(f"HTTP Error: {err}")
        return None
    except requests.exceptions.RequestException as err:
        print(f"Error: {err}")
        return None
    else:
        return payload


def consume_message(consumer, topic):
    topic_partition = TopicPartition(topic, partition=0)
    low, high = consumer.get_watermark_offsets(topic_partition)
    last_offset = high - 1
    consume_from = TopicPartition(topic, partition=0, offset=last_offset)
    consumer.assign([consume_from])
    while True:
        msg = consumer.poll(5.0)
        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                print(f"Reached end of topic {topic}")
            else:
                print(f"Error while consuming from topic {topic}: {msg.error()}")
        else:
            payload = json.loads(msg.value().decode("utf-8"))
            return payload


def main():
    bootstrap_servers = os.environ.get("BOOTSTRAP_SERVERS")
    topic = os.environ.get("TOPIC")
    sasl_user = os.environ.get("SASL_USER")
    sasl_password = os.environ.get("SASL_PASSWORD")

    conf = {
        "bootstrap.servers": bootstrap_servers,
        "security.protocol": "SASL_SSL",
        "sasl.mechanism": "PLAIN",
        "sasl.username": sasl_user,
        "sasl.password": sasl_password,
        "group.id": "somerandomgroupmakesureitisunique",
        "auto.offset.reset": "latest",
        "enable.auto.commit": False,
    }

    consumer = Consumer(conf)
    passed = 0
    failed = 0

    for i in range(10):
        print(f"Iteration {i+1}:")

        # Make order request
        payload = make_order_request()
        print(f"Order payload sent to Kong: {payload}")
        print("Sleeping 5 seconds to let the high watermark advance..")
        time.sleep(5)

        # Consume message from Kafka
        message_payload = consume_message(consumer, topic)
        if message_payload is None:
            print("No message received from Kafka")
            continue

        print(f"Received message payload from Kafka: {message_payload}")
        ret_request_body = message_payload.get('request').get('body')
        print(ret_request_body)
        print("--")
        print(payload)

        if ret_request_body == payload:
            print("Assertion passed")
            passed += 1
        else:
            print("Assertion failed")
            failed += 1

    print(f"\nReport: Passed {passed} times, Failed {failed} times")
    if failed > 0:
        print("Reason for failures: Received message does not match original order payload")


if __name__ == "__main__":
    main()


