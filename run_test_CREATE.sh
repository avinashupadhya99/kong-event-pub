#./reload.sh
sleep 2
curl -X POST http://localhost:8000/order -H 'Content-Type: application/json' \
 -d '{"order_id": "abcdef-12345", "items": [{"name": "foo", "quantity": 30}, {"name": "bar", "quantity": 42}]}'
