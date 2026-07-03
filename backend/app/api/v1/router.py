from fastapi import APIRouter

from app.api.v1.routes import auth, checkins, devices, health, hotline, identity, patients, staff

api_router = APIRouter()
api_router.include_router(health.router, tags=["health"])
api_router.include_router(auth.router, tags=["auth"])
api_router.include_router(patients.router, tags=["patients"])
api_router.include_router(checkins.router, tags=["checkins"])
api_router.include_router(staff.router, tags=["staff"])
api_router.include_router(hotline.router, tags=["hotline"])
api_router.include_router(devices.router, tags=["devices"])
api_router.include_router(identity.router, tags=["identity"])

