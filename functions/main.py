# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

# from firebase_functions import https_fn
# from firebase_admin import initialize_app, credentials

# cred = credentials.Certificate("service-account.json")

# initialize_app(cred)


# @https_fn.on_request()
# def on_request_example(req: https_fn.Request) -> https_fn.Response:
#     return https_fn.Response("Hello world!")

from firebase_functions import https_fn
from firebase_admin import initialize_app, firestore, auth, credentials
import numpy as np

cred = credentials.Certificate("service-account.json")

initialize_app(cred)

db = firestore.client()


@https_fn.on_request()
def analyze_vitals(req: https_fn.Request) -> https_fn.Response:
    if req.method != 'POST':
        return https_fn.Response("Only POST requests are accepted", status=405)

    # Check for Authorization header (required for auth)
    auth_header = req.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return https_fn.Response("Unauthorized: No valid token provided", status=401)

    # Extract and verify the ID token
    id_token = auth_header[7:]  # Remove "Bearer "
    try:
        decoded_token = auth.verify_id_token(id_token)
        print(
            f"User verified: UID = {decoded_token.get('uid', 'Unknown UID')}")
    except auth.InvalidIdTokenError as e:
        return https_fn.Response(f"Invalid token: {str(e)}", status=401)

    try:
        data = req.get_json()
        crew_id = data['crew_id']
        heart_rate = float(data['heart_rate'])
        sleep_hours = float(data['sleep_hours'])
        timestamp = data['timestamp']

        raw_stress = heart_rate * 0.6 - sleep_hours * 10
        # Minimum 0.1, maximum 100.0
        stress_score = max(0.1, min(100.0, raw_stress))
        stress_flag = 'High' if stress_score > 50 else 'Normal'

        doc_ref = db.collection('vitals').document(f'{crew_id}_{timestamp}')
        doc_ref.set({
            'crew_id': crew_id,
            'heart_rate': heart_rate,
            'sleep_hours': sleep_hours,
            'timestamp': timestamp,
            'stress_score': stress_score,
            'stress_flag': stress_flag,
            'processed_at': firestore.SERVER_TIMESTAMP
        })

        return https_fn.Response(f"Processed {crew_id}: Stress Score {stress_score}", status=201)
    except Exception as e:
        print(f"Error: {e}")
        return https_fn.Response("Error processing vitals", status=500)
