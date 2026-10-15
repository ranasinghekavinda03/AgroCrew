from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password
from app.db.models.user import User
from app.schemas.auth import LoginRequest, LoginResponse, UserCreate


DUMMY_PASSWORD_HASH = (
    "$argon2id$v=19$m=65536,t=3,p=4$+GJEoA+msXXE80zdHmKtdw$"
    "cMvUjY4maO/7gND2Jkp8rw1IsJ7mkD9h+wxMYHGELPY"
)


class DuplicateEmailError(Exception):
    pass


class RegistrationError(Exception):
    pass


class InvalidCredentialsError(Exception):
    pass


class AuthenticationServiceError(Exception):
    pass


def register_user(db: Session, registration: UserCreate) -> User:
    try:
        existing_user = db.scalar(
            select(User).where(func.lower(User.email) == registration.email)
        )
        if existing_user is not None:
            raise DuplicateEmailError

        user = User(
            name=registration.name,
            email=str(registration.email),
            password_hash=hash_password(registration.password),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        return user
    except DuplicateEmailError:
        db.rollback()
        raise
    except IntegrityError as error:
        db.rollback()
        if _is_email_unique_violation(error):
            raise DuplicateEmailError from None
        raise RegistrationError from None
    except SQLAlchemyError:
        db.rollback()
        raise RegistrationError from None


def authenticate_user(db: Session, credentials: LoginRequest) -> LoginResponse:
    try:
        user = db.scalar(
            select(User).where(func.lower(User.email) == str(credentials.email))
        )
        stored_hash = user.password_hash if user is not None else DUMMY_PASSWORD_HASH
        password_is_valid = verify_password(credentials.password, stored_hash)

        if user is None or not password_is_valid or not user.is_active:
            raise InvalidCredentialsError

        return LoginResponse(
            access_token=create_access_token(user.id),
            expires_in=settings.access_token_expire_minutes * 60,
        )
    except InvalidCredentialsError:
        raise
    except SQLAlchemyError:
        raise AuthenticationServiceError from None
    except Exception:
        raise AuthenticationServiceError from None


def _is_email_unique_violation(error: IntegrityError) -> bool:
    diagnostic = getattr(error.orig, "diag", None)
    constraint_name = getattr(diagnostic, "constraint_name", None)
    if constraint_name == "uq_users_email":
        return True

    error_message = str(error.orig).lower()
    return "uq_users_email" in error_message or "users.email" in error_message
