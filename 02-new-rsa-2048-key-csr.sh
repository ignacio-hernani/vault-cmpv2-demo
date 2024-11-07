#!/bin/bash

openssl req -nodes -newkey rsa:2048 -keyout "${CLIENT_KEY}" -out "${CLIENT_CSR}" -subj "/CN=super.example.com"
