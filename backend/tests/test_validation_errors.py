from fastapi.testclient import TestClient
import pytest


@pytest.mark.parametrize(
    ("path", "payload", "sensitive_value"),
    [
        (
            "/api/v1/auth/register",
            {
                "email": "audit@example.com",
                "password": "SensitiveRegistrationPassword123!",
            },
            "SensitiveRegistrationPassword123!",
        ),
        (
            "/api/v1/auth/login",
            {
                "email": "audit@example.com",
                "password": "SensitiveLoginPassword" * 8,
            },
            "SensitiveLoginPassword" * 8,
        ),
        (
            "/api/v1/auth/refresh",
            {"refresh_token": "sensitive-refresh-token-" + "x" * 512},
            "sensitive-refresh-token-" + "x" * 512,
        ),
        (
            "/api/v1/auth/logout",
            {"refresh_token": "sensitive-logout-token-" + "x" * 512},
            "sensitive-logout-token-" + "x" * 512,
        ),
    ],
)
def test_validation_errors_do_not_echo_sensitive_request_values(
    client: TestClient,
    path: str,
    payload: dict[str, str],
    sensitive_value: str,
) -> None:
    response = client.post(path, json=payload)

    assert response.status_code == 422
    assert sensitive_value not in response.text
    assert all("input" not in error for error in response.json()["detail"])
