#!/bin/bash

echo "Enter the VIN:"
read VIN

curl "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValuesExtended/$VIN?format=json" | jq
