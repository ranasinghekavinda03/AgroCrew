from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.db.models.user import User
from app.schemas.auth import UserCreate


class DuplicateEmailError(Exception):
    pass


class RegistrationError(Exception):
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


def _is_email_unique_violation(error: IntegrityError) -> bool:
    diagnostic = getattr(error.orig, "diag", None)
    constraint_name = getattr(diagnostic, "constraint_name", None)
    if constraint_name == "uq_users_email":
        return True

    error_message = str(error.orig).lower()
    return "uq_users_email" in error_message or "users.email" in error_message
