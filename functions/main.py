# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

# from firebase_functions import https_fn
# from firebase_admin import initialize_app

# initialize_app()


# @https_fn.on_request()
# def on_request_example(req: https_fn.Request) -> https_fn.Response:
#     return https_fn.Response("Hello world!")

from firebase_functions import https_fn
from firebase_admin import initialize_app, firestore
import numpy as np

initialize_app()
db = firestore.client()


@https_fn.on_request()
def analyze_vitals(req: https_fn.Request) -> https_fn.Response:
    if req.method != 'POST':
        return https_fn.Response("Only POST requests are accepted", status=405)
    try:
        data = req.get_json()
        crew_id = data['crew_id']
        heart_rate = float(data['heart_rate'])
        sleep_hours = float(data['sleep_hours'])
        timestamp = data['timestamp']

        stress_score = min(100, max(0, (heart_rate * 0.6 - sleep_hours * 10)))
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
