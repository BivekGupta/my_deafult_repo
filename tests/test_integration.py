import os
import requests
import pytest

# Target API gateway URL must be exported to environment variables
API_URL = os.environ.get("BASE_API_URL", "http://localhost:3000") 

def test_url_shortening_and_redirection():
    # Phase A: Shorten Path
    target_long_url = "https://amazon.com"
    payload = {"longUrl": target_long_url}
    
    post_response = requests.post(f"{API_URL}/shorten", json=payload)
    
    assert post_response.status_code == 201
    response_data = post_response.json()
    assert "shortId" in response_data
    
    short_id = response_data["shortId"]
    
    # Phase B: Redirect Path
    get_response = requests.get(f"{API_URL}/{short_id}", allow_redirects=False)
    
    assert get_response.status_code == 301
    assert get_response.headers["Location"] == target_long_url

def test_missing_payload_returns_400():
    post_response = requests.post(f"{API_URL}/shorten", json={})
    assert post_response.status_code == 400

def test_invalid_short_id_returns_404():
    get_response = requests.get(f"{API_URL}/nonExistentId123", allow_redirects=False)
    assert get_response.status_code == 404
