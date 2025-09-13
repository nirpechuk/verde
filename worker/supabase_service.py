from typing import List, Optional
from supabase_client import supabase
from models import User, AppMarker, Issue, Event, Report


class SupabaseService:
    """Service class for interacting with Supabase database"""

    # User operations
    @staticmethod
    def get_users(limit: int = 100) -> List[User]:
        try:
            response = supabase.table("users").select("*").limit(limit).execute()
            return [User(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching users: {e}")
            return []

    @staticmethod
    def get_user(user_id: str) -> Optional[User]:
        try:
            response = supabase.table("users").select("*").eq("id", user_id).execute()
            if response.data:
                return User(**response.data[0])
            return None
        except Exception as e:
            print(f"Error fetching user: {e}")
            return None

    @staticmethod
    def create_user(user: User) -> Optional[User]:
        try:
            data = user.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            response = supabase.table("users").insert(data).execute()
            if response.data:
                return User(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating user: {e}")
            return None

    # Marker operations
    @staticmethod
    def get_markers(limit: int = 100) -> List[AppMarker]:
        try:
            response = supabase.table("markers").select("*").limit(limit).execute()
            return [AppMarker(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching markers: {e}")
            return []

    @staticmethod
    def create_marker(marker: AppMarker) -> Optional[AppMarker]:
        try:
            data = marker.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["created_by"] = str(data["created_by"])  # Convert UUID to string
            response = supabase.table("markers").insert(data).execute()
            if response.data:
                return AppMarker(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating marker: {e}")
            return None

    # Issue operations
    @staticmethod
    def get_issues(limit: int = 100) -> List[Issue]:
        try:
            response = supabase.table("issues").select("*").limit(limit).execute()
            return [Issue(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching issues: {e}")
            return []

    @staticmethod
    def create_issue(issue: Issue) -> Optional[Issue]:
        try:
            data = issue.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["marker_id"] = str(data["marker_id"])  # Convert UUID to string
            response = supabase.table("issues").insert(data).execute()
            if response.data:
                return Issue(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating issue: {e}")
            return None

    # Event operations
    @staticmethod
    def get_events(limit: int = 100) -> List[Event]:
        try:
            response = supabase.table("events").select("*").limit(limit).execute()
            return [Event(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching events: {e}")
            return []

    @staticmethod
    def create_event(event: Event) -> Optional[Event]:
        try:
            data = event.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            data["marker_id"] = str(data["marker_id"])  # Convert UUID to string
            response = supabase.table("events").insert(data).execute()
            if response.data:
                return Event(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating event: {e}")
            return None

    # Report operations
    @staticmethod
    def get_reports(limit: int = 100) -> List[Report]:
        try:
            response = supabase.table("reports").select("*").limit(limit).execute()
            return [Report(**item) for item in response.data]
        except Exception as e:
            print(f"Error fetching reports: {e}")
            return []

    @staticmethod
    def create_report(report: Report) -> Optional[Report]:
        try:
            data = report.dict(exclude_unset=True)
            data["id"] = str(data["id"])  # Convert UUID to string
            if data.get("created_by"):
                data["created_by"] = str(data["created_by"])  # Convert UUID to string
            response = supabase.table("reports").insert(data).execute()
            if response.data:
                return Report(**response.data[0])
            return None
        except Exception as e:
            print(f"Error creating report: {e}")
            return None
