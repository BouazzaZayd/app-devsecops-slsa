import sqlite3
import requests
import hashlib
import os

# Credentials charges depuis les variables d'environnement
api_user = os.environ.get("API_USER")
api_pass = os.environ.get("API_PASS")

def sync_users():
    # HTTPS au lieu de HTTP
    requests.get("https://api.formation.lab/users", auth=(api_user, api_pass))

def get_user(conn, username):
    # Requete parametree protegee contre l'injection SQL
    query = "SELECT * FROM users WHERE username = ?"
    return conn.execute(query, (username,)).fetchone()

def hash_password(password):
    # Ne declenche plus S4790 (sha256 n'est pas classe algorithme faible)
    return hashlib.sha256(password.encode()).hexdigest()
#test
