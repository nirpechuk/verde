from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field
from pydantic.types import UUID4


class User(BaseModel):
    id: UUID4
    email: Optional[str] = None
    username: Optional[str] = None
    points: int = Field(default=0)
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}  # Convert UUID to string when serializing


class MarkerType(str, Enum):
    issue = "issue"
    event = "event"


class AppMarker(BaseModel):
    id: UUID4
    type: MarkerType
    latitude: float
    longitude: float
    created_by: UUID4
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class IssueCategory(str, Enum):
    waste = "waste"
    pollution = "pollution"
    water = "water"
    other = "other"


class IssueStatus(str, Enum):
    active = "active"
    resolved = "resolved"
    removed = "removed"


class Issue(BaseModel):
    id: UUID4
    marker_id: UUID4
    title: str
    description: Optional[str] = None
    category: IssueCategory
    image_url: Optional[str] = None
    credibility_score: int = Field(default=0)
    status: IssueStatus = Field(default=IssueStatus.active)
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class EventCategory(str, Enum):
    cleanup = "cleanup"
    advocacy = "advocacy"
    education = "education"
    other = "other"


class EventStatus(str, Enum):
    upcoming = "upcoming"
    active = "active"
    completed = "completed"
    cancelled = "cancelled"


class Event(BaseModel):
    id: UUID4
    marker_id: UUID4
    title: str
    description: Optional[str] = None
    category: EventCategory
    start_time: datetime
    end_time: datetime
    max_participants: Optional[int] = None
    current_participants: int = Field(default=0)
    status: EventStatus = Field(default=EventStatus.upcoming)
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class Report(BaseModel):
    id: UUID4
    created_by: Optional[UUID4] = None
    label: int = Field(default=0)
    severity: int = Field(default=0)
    status: int = Field(default=0)
    location: dict  # GeoJSON format
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class IssueVote(BaseModel):
    id: UUID4
    issue_id: UUID4
    user_id: UUID4
    vote: int  # -1 or 1
    created_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class EventRSVP(BaseModel):
    id: UUID4
    event_id: UUID4
    user_id: UUID4
    status: str = Field(default="going")  # going, maybe, not_going
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}


class UserPointsHistory(BaseModel):
    id: UUID4
    user_id: UUID4
    action_type: str  # report_issue, create_event, rsvp_event, vote_issue
    points: int
    reference_id: Optional[UUID4] = None
    created_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {UUID4: str}
