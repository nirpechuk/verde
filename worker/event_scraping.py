#!/usr/bin/env python3
"""
Open311 Event Scraping System

This script scrapes Open311 APIs from multiple cities across the country to find
environmental issues and convert them into cleanup/advocacy events.

Open311 is a standardized API for civic issue reporting used by many cities.
We focus on environmental categories like waste, pollution, water issues, etc.

Features:
- Multi-city support (Boston, Chicago, San Francisco, etc.)
- Environmental issue filtering
- Automatic event creation from issues
- Rate limiting and error handling
- Geospatial clustering of nearby issues
"""

import asyncio
import aiohttp
import time
import uuid
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from urllib.parse import urljoin
import json
import logging

from supabase_service import SupabaseService
from models import AppMarker, Event, MarkerType, EventCategory, EventStatus

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class CityConfig:
    """Configuration for a city's Open311 API"""
    name: str
    jurisdiction_id: str
    base_url: str
    api_key: Optional[str] = None
    rate_limit_delay: float = 1.0  # seconds between requests


@dataclass
class Open311Issue:
    """Represents an issue from Open311 API"""
    service_request_id: str
    service_name: str
    service_code: str
    description: str
    status: str
    lat: float
    lng: float
    address: str
    requested_datetime: datetime
    updated_datetime: datetime
    agency_responsible: str = ""
    media_url: str = ""


class Open311Scraper:
    """Scrapes Open311 APIs and converts issues to environmental events"""
    
    # Major cities with Open311 APIs (updated with working endpoints)
    CITIES = [
        CityConfig(
            name="Baltimore",
            jurisdiction_id="baltimorecity.gov",
            base_url="http://311.baltimorecity.gov/open311/v2/",  # Working endpoint
        ),
        CityConfig(
            name="Bloomington",
            jurisdiction_id="bloomington.in.gov",
            base_url="https://bloomington.in.gov/crm/open311/v2/",  # Working endpoint
        ),
        CityConfig(
            name="Brookline",
            jurisdiction_id="brooklinema.gov",
            base_url="http://spot.brooklinema.gov/open311/v2/",  # Working endpoint
        ),
        CityConfig(
            name="Chicago", 
            jurisdiction_id="chicago.gov",
            base_url="http://311api.cityofchicago.org/open311/v2/",  # Updated to HTTP
        ),
        # Fallback cities for demo purposes
        CityConfig(
            name="Boston",
            jurisdiction_id="boston.gov",
            base_url="https://mayors24.cityofboston.gov/open311/v2/",  # Will fail, triggers fallback
        ),
    ]
    
    # Environmental service categories to look for
    ENVIRONMENTAL_KEYWORDS = [
        "waste", "trash", "garbage", "recycling", "litter", "dumping",
        "pollution", "water", "air quality", "environmental", "cleanup",
        "hazardous", "toxic", "contamination", "spill", "leak",
        "graffiti", "vandalism", "park", "tree", "vegetation",
        "sanitation", "pest", "rodent", "illegal dumping"
    ]
    
    # Service codes that are typically environmental (varies by city)
    ENVIRONMENTAL_SERVICE_CODES = [
        "001", "002", "003",  # Common waste/sanitation codes
        "PWD", "DPW", "ENV",  # Department codes
    ]

    def __init__(self, use_fallback: bool = True):
        self.session: Optional[aiohttp.ClientSession] = None
        self.created_events_count = 0
        self.processed_issues_count = 0
        self.use_fallback = use_fallback
        self.fallback_events_created = 0

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30),
            headers={'User-Agent': 'Environmental-Platform-Scraper/1.0'}
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def get_services(self, city: CityConfig) -> List[Dict]:
        """Get available services for a city"""
        url = urljoin(city.base_url, "services.json")
        params = {"jurisdiction_id": city.jurisdiction_id}
        
        if city.api_key:
            params["api_key"] = city.api_key
            
        try:
            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    return data if isinstance(data, list) else data.get("services", [])
                else:
                    logger.warning(f"Failed to get services for {city.name}: {response.status}")
                    return []
        except Exception as e:
            logger.error(f"Error getting services for {city.name}: {e}")
            return []

    async def get_service_requests(self, city: CityConfig, service_code: str = None, 
                                 days_back: int = 7) -> List[Open311Issue]:
        """Get service requests for a city, optionally filtered by service code"""
        url = urljoin(city.base_url, "requests.json")
        
        # Get requests from the last week by default
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)
        
        params = {
            "jurisdiction_id": city.jurisdiction_id,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "status": "open",  # Focus on open issues that could become events
        }
        
        if service_code:
            params["service_code"] = service_code
            
        if city.api_key:
            params["api_key"] = city.api_key
            
        try:
            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    requests_data = data if isinstance(data, list) else data.get("service_requests", [])
                    return self._parse_issues(requests_data, city.name)
                else:
                    logger.warning(f"Failed to get requests for {city.name}: {response.status}")
                    return []
        except Exception as e:
            logger.error(f"Error getting requests for {city.name}: {e}")
            return []

    def _parse_issues(self, requests_data: List[Dict], city_name: str) -> List[Open311Issue]:
        """Parse raw API response into Open311Issue objects"""
        issues = []
        
        for request_data in requests_data:
            try:
                # Skip if missing required location data
                if not request_data.get("lat") or not request_data.get("long"):
                    continue
                    
                # Parse datetime fields
                requested_dt = self._parse_datetime(request_data.get("requested_datetime"))
                updated_dt = self._parse_datetime(request_data.get("updated_datetime"))
                
                if not requested_dt:
                    continue
                    
                issue = Open311Issue(
                    service_request_id=str(request_data.get("service_request_id", "")),
                    service_name=request_data.get("service_name", ""),
                    service_code=request_data.get("service_code", ""),
                    description=request_data.get("description", ""),
                    status=request_data.get("status", "open"),
                    lat=float(request_data["lat"]),
                    lng=float(request_data["long"]),
                    address=request_data.get("address", ""),
                    requested_datetime=requested_dt,
                    updated_datetime=updated_dt or requested_dt,
                    agency_responsible=request_data.get("agency_responsible", ""),
                    media_url=request_data.get("media_url", "")
                )
                issues.append(issue)
                
            except (ValueError, KeyError, TypeError) as e:
                logger.debug(f"Skipping malformed request from {city_name}: {e}")
                continue
                
        return issues

    def _parse_datetime(self, dt_str: str) -> Optional[datetime]:
        """Parse datetime string from Open311 API"""
        if not dt_str:
            return None
            
        # Try common datetime formats
        formats = [
            "%Y-%m-%dT%H:%M:%S%z",      # ISO with timezone
            "%Y-%m-%dT%H:%M:%S",        # ISO without timezone
            "%Y-%m-%d %H:%M:%S",        # Space separated
            "%Y-%m-%dT%H:%M:%S.%f%z",   # With microseconds and timezone
        ]
        
        for fmt in formats:
            try:
                return datetime.strptime(dt_str, fmt)
            except ValueError:
                continue
                
        logger.debug(f"Could not parse datetime: {dt_str}")
        return None

    def is_environmental_issue(self, issue: Open311Issue) -> bool:
        """Determine if an issue is environmental and suitable for event creation"""
        # Check service name and description for environmental keywords
        text_to_check = f"{issue.service_name} {issue.description}".lower()
        
        for keyword in self.ENVIRONMENTAL_KEYWORDS:
            if keyword in text_to_check:
                return True
                
        # Check service code
        if issue.service_code in self.ENVIRONMENTAL_SERVICE_CODES:
            return True
            
        return False

    def cluster_nearby_issues(self, issues: List[Open311Issue], 
                            max_distance_km: float = 0.5) -> List[List[Open311Issue]]:
        """Group nearby issues that could become a single cleanup event"""
        if not issues:
            return []
            
        clusters = []
        used_indices = set()
        
        for i, issue in enumerate(issues):
            if i in used_indices:
                continue
                
            cluster = [issue]
            used_indices.add(i)
            
            # Find nearby issues
            for j, other_issue in enumerate(issues):
                if j in used_indices or i == j:
                    continue
                    
                distance = self._haversine_distance(
                    issue.lat, issue.lng,
                    other_issue.lat, other_issue.lng
                )
                
                if distance <= max_distance_km:
                    cluster.append(other_issue)
                    used_indices.add(j)
                    
            clusters.append(cluster)
            
        return clusters

    def _haversine_distance(self, lat1: float, lng1: float, 
                          lat2: float, lng2: float) -> float:
        """Calculate distance between two points in kilometers"""
        from math import radians, cos, sin, asin, sqrt
        
        # Convert to radians
        lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
        
        # Haversine formula
        dlat = lat2 - lat1
        dlng = lng2 - lng1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
        c = 2 * asin(sqrt(a))
        
        # Earth's radius in kilometers
        r = 6371
        return c * r

    def create_event_from_cluster(self, cluster: List[Open311Issue], 
                                city_name: str) -> Optional[Event]:
        """Create an environmental event from a cluster of related issues"""
        if not cluster:
            return None
            
        # Use the most recent issue as the primary one
        primary_issue = max(cluster, key=lambda x: x.requested_datetime)
        
        # Calculate center point of cluster
        center_lat = sum(issue.lat for issue in cluster) / len(cluster)
        center_lng = sum(issue.lng for issue in cluster) / len(cluster)
        
        # Determine event category based on issue types
        category = self._determine_event_category(cluster)
        
        # Create event title and description
        title = self._generate_event_title(cluster, city_name, category)
        description = self._generate_event_description(cluster, primary_issue)
        
        # Schedule event for next weekend (Saturday)
        now = datetime.now()
        days_until_saturday = (5 - now.weekday()) % 7
        if days_until_saturday == 0:  # If today is Saturday, schedule for next Saturday
            days_until_saturday = 7
            
        event_start = now.replace(hour=10, minute=0, second=0, microsecond=0) + \
                     timedelta(days=days_until_saturday)
        event_end = event_start + timedelta(hours=3)  # 3-hour events
        
        # Create marker first
        marker = AppMarker(
            id=uuid.uuid4(),
            type=MarkerType.event,
            latitude=center_lat,
            longitude=center_lng,
            created_by=uuid.uuid4(),  # System-generated events
            created_at=datetime.now(),
            updated_at=datetime.now()
        )
        
        created_marker = SupabaseService.create_marker(marker)
        if not created_marker:
            logger.error("Failed to create marker for event")
            return None
            
        # Create event
        event = Event(
            id=uuid.uuid4(),
            marker_id=created_marker.id,
            title=title,
            description=description,
            category=category,
            start_time=event_start,
            end_time=event_end,
            max_participants=25,  # Reasonable size for cleanup events
            current_participants=0,
            status=EventStatus.upcoming,
            created_at=datetime.now(),
            updated_at=datetime.now()
        )
        
        return SupabaseService.create_event(event)

    def _determine_event_category(self, cluster: List[Open311Issue]) -> EventCategory:
        """Determine the best event category based on the issues"""
        text = " ".join(f"{issue.service_name} {issue.description}" for issue in cluster).lower()
        
        if any(word in text for word in ["cleanup", "trash", "waste", "litter", "dumping"]):
            return EventCategory.cleanup
        elif any(word in text for word in ["advocacy", "policy", "petition", "meeting"]):
            return EventCategory.advocacy
        elif any(word in text for word in ["education", "awareness", "workshop", "training"]):
            return EventCategory.education
        else:
            return EventCategory.cleanup  # Default to cleanup for environmental issues

    def _generate_event_title(self, cluster: List[Open311Issue], 
                            city_name: str, category: EventCategory) -> str:
        """Generate a descriptive event title"""
        area = cluster[0].address.split(",")[0] if cluster[0].address else "Community"
        
        if category == EventCategory.cleanup:
            return f"{area} Environmental Cleanup - {city_name}"
        elif category == EventCategory.advocacy:
            return f"{area} Environmental Action Meeting - {city_name}"
        elif category == EventCategory.education:
            return f"{area} Environmental Awareness Workshop - {city_name}"
        else:
            return f"{area} Environmental Event - {city_name}"

    def _generate_event_description(self, cluster: List[Open311Issue], 
                                  primary_issue: Open311Issue) -> str:
        """Generate a detailed event description"""
        issue_count = len(cluster)
        area = primary_issue.address.split(",")[0] if primary_issue.address else "the area"
        
        description = f"Join us for a community environmental event in {area}! "
        
        if issue_count == 1:
            description += f"We're addressing a reported {primary_issue.service_name.lower()} issue. "
        else:
            description += f"We're addressing {issue_count} related environmental issues in the area. "
            
        description += f"Issues include: {primary_issue.service_name}"
        if primary_issue.description:
            description += f" - {primary_issue.description[:100]}..."
            
        description += "\n\nWhat we'll provide:\n"
        description += "• All necessary cleanup supplies\n"
        description += "• Safety equipment and gloves\n"
        description += "• Refreshments and snacks\n"
        description += "• Community service hours documentation\n\n"
        description += "This event was automatically created based on community-reported issues. "
        description += "Help us keep our neighborhoods clean and healthy!"
        
        return description

    async def scrape_city(self, city: CityConfig) -> List[Event]:
        """Scrape a single city and create events"""
        logger.info(f"🌆 Scraping {city.name}...")
        
        # Get available services to understand what the city tracks
        services = await self.get_services(city)
        environmental_services = [
            s for s in services 
            if any(keyword in s.get("service_name", "").lower() 
                  for keyword in self.ENVIRONMENTAL_KEYWORDS)
        ]
        
        logger.info(f"Found {len(environmental_services)} environmental services in {city.name}")
        
        # Get all recent service requests
        all_issues = await self.get_service_requests(city, days_back=14)
        logger.info(f"Retrieved {len(all_issues)} total issues from {city.name}")
        
        # Filter for environmental issues
        env_issues = [issue for issue in all_issues if self.is_environmental_issue(issue)]
        logger.info(f"Found {len(env_issues)} environmental issues in {city.name}")
        
        if not env_issues:
            return []
            
        # Cluster nearby issues
        clusters = self.cluster_nearby_issues(env_issues)
        logger.info(f"Created {len(clusters)} issue clusters in {city.name}")
        
        # Create events from clusters
        created_events = []
        for cluster in clusters:
            if len(cluster) >= 1:  # Create events for single issues or clusters
                event = self.create_event_from_cluster(cluster, city.name)
                if event:
                    created_events.append(event)
                    self.created_events_count += 1
                    logger.info(f"✅ Created event: {event.title}")
                    
                # Rate limiting
                await asyncio.sleep(city.rate_limit_delay)
                
        self.processed_issues_count += len(env_issues)
        
        # If no events were created and fallback is enabled, create sample events
        if not created_events and self.use_fallback:
            logger.info(f"No events created from API data for {city.name}, using fallback...")
            created_events = self.create_fallback_events(city.name)
            
        return created_events

    async def scrape_all_cities(self) -> Dict[str, List[Event]]:
        """Scrape all configured cities and create events"""
        logger.info("🚀 Starting Open311 environmental event scraping...")
        
        results = {}
        for city in self.CITIES:
            try:
                events = await self.scrape_city(city)
                results[city.name] = events
                logger.info(f"Created {len(events)} events for {city.name}")
                
                # Rate limiting between cities
                await asyncio.sleep(2.0)
                
            except Exception as e:
                logger.error(f"Failed to scrape {city.name}: {e}")
                results[city.name] = []
                
        return results


async def main():
    """Main scraping function"""
    print("🌍 Open311 Environmental Event Scraper")
    print("=" * 50)
    
    async with Open311Scraper() as scraper:
        results = await scraper.scrape_all_cities()
        
        total_events = sum(len(events) for events in results.values())
        
        print(f"\n📊 Scraping Results:")
        print(f"Cities processed: {len(results)}")
        print(f"Total events created: {total_events}")
        print(f"API-sourced events: {scraper.created_events_count}")
        print(f"Fallback events: {scraper.fallback_events_created}")
        print(f"Total issues processed: {scraper.processed_issues_count}")
        
        for city_name, events in results.items():
            if events:
                print(f"  • {city_name}: {len(events)} events")
                for event in events[:2]:  # Show first 2 events per city
                    print(f"    - {event.title}")
            else:
                print(f"  • {city_name}: 0 events")
            
        print(f"\n✨ Scraping completed!")
        if total_events > 0:
            print("🎉 Events successfully created! Check your Supabase dashboard to see them.")
            print("\n💡 Next steps:")
            print("• Review the generated events in your dashboard")
            print("• Customize event details as needed")
            print("• Share events with your community")
        else:
            print("⚠️  No events were created. Check your Supabase connection and try again.")


if __name__ == "__main__":
    asyncio.run(main())
