use axum::{
    Json, Router,
    http::{HeaderMap, StatusCode},
    routing::post,
};
use chrono::Utc;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::net::TcpListener;

#[derive(Serialize, Deserialize, Debug)]
struct VitalsRequest {
    crew_id: String,
    heart_rate: f64,
    sleep_hours: f64,
    timestamp: String,
}

#[derive(Serialize)]
struct VitalsResponse {
    message: String,
    status: String,
}

async fn verify_id_token(client: &Client, token: &str) -> Result<String, String> {
    let url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=AIzaSyBcuUBuau6oIBmqXZRYtqhHCDMN-FNjlwI";
    let res = client
        .post(url)
        .json(&json!({"idToken": token}))
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;

    let json: serde_json::Value = res
        .json()
        .await
        .map_err(|e| format!("JSON parse failed: {}", e))?;

    if let Some(error) = json.get("error") {
        return Err(format!(
            "Firebase error: {}",
            error["message"].as_str().unwrap_or("Unknown error")
        ));
    }

    let users = json
        .get("users")
        .and_then(|u| u.as_array())
        .ok_or("No users in response")?;
    let uid = users[0]
        .get("localId")
        .and_then(|id| id.as_str())
        .ok_or("No UID found")?;
    Ok(uid.to_string())
}

async fn get_access_token(client: &Client) -> Result<String, String> {
    let metadata_url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";
    let res = client
        .get(metadata_url)
        .header("Metadata-Flavor", "Google")
        .send()
        .await;

    match res {
        Ok(response) if response.status().is_success() => {
            let json: serde_json::Value = response
                .json()
                .await
                .map_err(|e| format!("Token parse failed: {}", e))?;
            json.get("access_token")
                .and_then(|t| t.as_str())
                .map(String::from)
                .ok_or("No access token in metadata response".to_string())
        }
        _ => {
            let output = std::process::Command::new("gcloud")
                .args(&["auth", "print-access-token"])
                .output()
                .map_err(|e| format!("Failed to run gcloud: {}", e))?;
            let token = String::from_utf8(output.stdout)
                .map_err(|e| format!("Invalid token output: {}", e))?
                .trim()
                .to_string();
            if token.is_empty() {
                return Err("No access token from ADC".to_string());
            }
            Ok(token)
        }
    }
}

async fn save_to_firestore(
    client: &Client,
    vitals: &VitalsRequest,
    stress_score: f64,
    stress_flag: &str,
    uid: &str,
) -> Result<(), String> {
    let access_token = get_access_token(client).await?;
    let project_id = "mars-mind";
    let url = format!(
        "https://firestore.googleapis.com/v1/projects/{}/databases/(default)/documents/users/{}/vitals/{}?access_token={}",
        project_id,
        uid,
        vitals.timestamp.replace(":", "_"), // Use timestamp as doc ID, sanitized
        access_token
    );
    let body = json!({
        "fields": {
            "crew_id": {"stringValue": vitals.crew_id.clone()},
            "heart_rate": {"doubleValue": vitals.heart_rate},
            "sleep_hours": {"doubleValue": vitals.sleep_hours},
            "timestamp": {"stringValue": vitals.timestamp.clone()},
            "stress_score": {"doubleValue": stress_score},
            "stress_flag": {"stringValue": stress_flag},
            "processed_at": {"timestampValue": Utc::now().to_rfc3339()}
        }
    });

    println!("Saving to Firestore - URL: {}", url);
    println!("Request body: {}", serde_json::to_string(&body).unwrap());

    let response = client
        .patch(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("Firestore request failed: {}", e))?;

    let status = response.status();
    let response_text = response
        .text()
        .await
        .unwrap_or_else(|_| "Failed to get response text".to_string());
    println!("Firestore response status: {}", status);
    println!("Firestore response body: {}", response_text);

    if !status.is_success() {
        return Err(format!("Firestore write failed with status: {}", status));
    }

    Ok(())
}

async fn analyze_vitals(
    headers: HeaderMap,
    Json(vitals): Json<VitalsRequest>,
) -> (StatusCode, Json<VitalsResponse>) {
    let client = Client::new();

    let auth_header = match headers.get("Authorization") {
        Some(h) => h.to_str().unwrap_or(""),
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(VitalsResponse {
                    message: "Unauthorized: No token provided".to_string(),
                    status: "error".to_string(),
                }),
            );
        }
    };

    if !auth_header.starts_with("Bearer ") {
        return (
            StatusCode::UNAUTHORIZED,
            Json(VitalsResponse {
                message: "Unauthorized: Invalid token format".to_string(),
                status: "error".to_string(),
            }),
        );
    }
    let id_token = &auth_header[7..];

    let uid = match verify_id_token(&client, id_token).await {
        Ok(uid) => {
            println!("User verified: UID = {}", uid);
            uid
        }
        Err(e) => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(VitalsResponse {
                    message: format!("Invalid token: {}", e),
                    status: "error".to_string(),
                }),
            );
        }
    };

    let raw_stress = vitals.heart_rate * 0.6 - vitals.sleep_hours * 10.0;
    let stress_score = raw_stress.clamp(0.1, 100.0);
    let stress_flag = if stress_score > 50.0 { "High" } else { "Normal" };

    if let Err(e) = save_to_firestore(&client, &vitals, stress_score, stress_flag, &uid).await {
        println!("Error: {}", e);
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(VitalsResponse {
                message: "Error processing vitals".to_string(),
                status: "error".to_string(),
            }),
        );
    }

    (
        StatusCode::CREATED,
        Json(VitalsResponse {
            message: format!("Processed {}: Stress Score {}", vitals.crew_id, stress_score),
            status: "success".to_string(),
        }),
    )
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/analyze_vitals", post(analyze_vitals));
    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], 8080));
    let listener = TcpListener::bind(addr).await.unwrap();
    println!("Listening on {}", listener.local_addr().unwrap());
    axum::serve(listener, app).await.unwrap();
}

// #[tokio::main]
// async fn main() {
//     let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string()).parse::<u16>().unwrap();
//     let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));
//     let listener = TcpListener::bind(addr).await.unwrap();
//     println!("Listening on {}", listener.local_addr().unwrap());
//     let app = Router::new().route("/analyze_vitals", post(analyze_vitals));
//     axum::serve(listener, app).await.unwrap();
// }