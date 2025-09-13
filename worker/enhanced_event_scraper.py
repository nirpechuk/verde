#!/usr/bin/env python3
"""
Enhanced Environmental Event Scraper

Uses Socrata APIs to access 311 data from major cities and creates intelligent
environmental events with proper categorization and descriptions.

Data Sources:
- NYC Open Data (Socrata API)
- Chicago Data Portal (Socrata API) 
- San Francisco DataSF (Socrata API)
- Los Angeles Open Data (Socrata API)
"""

import asyncio
import aiohttp
import uuid
import re
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
import json
import logging

from supabase_service import SupabaseService
from models import AppMarker, Event, MarkerType, EventCategory, EventStatus

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class SocrataConfig:
    """Configuration for a city's Socrata API"""
    name: str
    base_url: str
    dataset_id: str
    app_token: Optional[str] = None
    rate_limit_delay: float = 0.5


@dataclass
class EnvironmentalIssue:
    """Represents an environmental issue from 311 data"""
    unique_key: str
    complaint_type: str
    descriptor: str
    incident_address: str
    city: str
    status: str
    lat: float
    lng: float
    created_date: datetime
    closed_date: Optional[datetime]
    agency: str
    resolution_description: str = ""


class EnhancedEventScraper:
    """Enhanced scraper using Socrata APIs with intelligent event generation"""
    
    # Major cities with Socrata-powered open data
    CITIES = [
        SocrataConfig(
            name="New York City",
            base_url="https://data.cityofnewyork.us/resource",
            dataset_id="erm2-nwe9",  # 311 Service Requests from 2010 to Present
        ),
        SocrataConfig(
            name="Chicago",
            base_url="https://data.cityofchicago.org/resource",
            dataset_id="v6vf-nfxy",  # 311 Service Requests
        ),
        SocrataConfig(
            name="San Francisco",
            base_url="https://data.sfgov.org/resource",
            dataset_id="vw6y-z8j6",  # 311 Cases
        ),
        SocrataConfig(
            name="Los Angeles",
            base_url="https://data.lacity.org/resource",
            dataset_id="pvft-t768",  # MyLA311 Service Request Data
        ),
    ]
    
    # Environmental complaint types and their mappings to event categories
    ENVIRONMENTAL_MAPPINGS = {
        # Cleanup events
        "cleanup": {
            "keywords": [
                "illegal dumping", "litter", "trash", "garbage", "debris", "waste",
                "graffiti", "abandoned vehicle", "bulk item", "mattress", "furniture",
                "construction debris", "yard waste", "electronic waste", "hazardous waste",
                "street cleaning", "sidewalk cleaning", "park maintenance", "beach cleanup"
            ],
            "complaint_types": [
                "Illegal Dumping", "Street/Sidewalk", "Sanitation Condition", "Graffiti",
                "Abandoned Vehicle", "Bulk Item", "Dead Animal", "Overflowing Litter Baskets",
                "Dirty Conditions", "Sweeping/Cleaning", "Litter Basket / Request"
            ],
            "category": EventCategory.cleanup
        },
        
        # Advocacy events  
        "advocacy": {
            "keywords": [
                "air quality", "noise", "pollution", "environmental", "toxic", "contamination",
                "industrial", "emissions", "odor", "chemical", "hazmat", "spill", "leak",
                "water quality", "sewage", "storm drain", "illegal discharge"
            ],
            "complaint_types": [
                "Air Quality", "Noise", "Water Quality", "Industrial Waste", "Hazmat",
                "Environmental", "Toxic Material", "Chemical Spill", "Sewage",
                "Illegal Discharge", "Odor/Gas", "Indoor Air Quality"
            ],
            "category": EventCategory.advocacy
        },
        
        # Education events
        "education": {
            "keywords": [
                "recycling", "composting", "sustainability", "green", "energy",
                "conservation", "education", "outreach", "awareness", "program"
            ],
            "complaint_types": [
                "Recycling", "Composting", "Energy", "Green Program", "Sustainability",
                "Environmental Education", "Conservation"
            ],
            "category": EventCategory.education
        }
    }
    
    # Agency mappings for better event descriptions
    AGENCY_FOCUS = {
        "DSNY": "waste management and sanitation",
        "DEP": "environmental protection and water quality", 
        "DOT": "transportation and street maintenance",
        "DPR": "parks and recreation facilities",
        "HPD": "housing and building conditions",
        "DOHMH": "public health and safety",
        "Streets and Sanitation": "street cleaning and waste collection",
        "Environment": "environmental compliance and protection",
        "Public Works": "infrastructure and maintenance"
    }

    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None
        self.created_events_count = 0
        self.processed_issues_count = 0

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=60),
            headers={'User-Agent': 'Environmental-Platform-Enhanced-Scraper/1.0'}
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def fetch_311_data(self, city: SocrataConfig, days_back: int = 7) -> List[EnvironmentalIssue]:
        """Fetch 311 data from Socrata API"""
        logger.info(f"🌆 Fetching data from {city.name}...")
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)
        
        # Build Socrata API URL
        url = f"{city.base_url}/{city.dataset_id}.json"
        
        # Build query parameters for environmental issues
        env_types = []
        for category_data in self.ENVIRONMENTAL_MAPPINGS.values():
            env_types.extend(category_data["complaint_types"])
        
        # Create WHERE clause for environmental complaint types
        complaint_filter = " OR ".join([f"complaint_type='{ct}'" for ct in env_types[:10]])  # Limit for URL length
        
        params = {
            "$where": f"created_date >= '{start_date.isoformat()}' AND ({complaint_filter})",
            "$limit": 1000,
            "$order": "created_date DESC"
        }
        
        if city.app_token:
            params["$$app_token"] = city.app_token
            
        try:
            async with self.session.get(url, params=params) as response:
                if response.status == 200:
                    data = await response.json()
                    return self._parse_socrata_data(data, city.name)
                else:
                    logger.warning(f"Failed to fetch data from {city.name}: {response.status}")
                    return []
        except Exception as e:
            logger.error(f"Error fetching data from {city.name}: {e}")
            return []

    def _parse_socrata_data(self, data: List[Dict], city_name: str) -> List[EnvironmentalIssue]:
        """Parse Socrata API response into EnvironmentalIssue objects"""
        issues = []
        
        for item in data:
            try:
                # Handle different field names across cities
                lat = self._safe_float(item.get("latitude") or item.get("lat"))
                lng = self._safe_float(item.get("longitude") or item.get("lng") or item.get("long"))
                
                if not lat or not lng:
                    continue
                    
                # Parse created date
                created_date = self._parse_socrata_date(
                    item.get("created_date") or item.get("opened_date") or item.get("requested_datetime")
                )
                if not created_date:
                    continue
                    
                # Parse closed date
                closed_date = self._parse_socrata_date(
                    item.get("closed_date") or item.get("resolved_date") or item.get("updated_datetime")
                )
                
                issue = EnvironmentalIssue(
                    unique_key=str(item.get("unique_key") or item.get("service_request_number") or item.get("case_id", "")),
                    complaint_type=item.get("complaint_type") or item.get("service_name") or item.get("category", ""),
                    descriptor=item.get("descriptor") or item.get("service_subtype") or item.get("source", ""),
                    incident_address=item.get("incident_address") or item.get("address") or item.get("point", {}).get("human_address", ""),
                    city=city_name,
                    status=item.get("status") or "Open",
                    lat=lat,
                    lng=lng,
                    created_date=created_date,
                    closed_date=closed_date,
                    agency=item.get("agency") or item.get("agency_name") or "",
                    resolution_description=item.get("resolution_description") or item.get("resolution_action") or ""
                )
                issues.append(issue)
                
            except Exception as e:
                logger.debug(f"Skipping malformed record from {city_name}: {e}")
                continue
                
        return issues

    def _safe_float(self, value) -> Optional[float]:
        """Safely convert value to float"""
        if value is None:
            return None
        try:
            return float(value)
        except (ValueError, TypeError):
            return None

    def _parse_socrata_date(self, date_str: str) -> Optional[datetime]:
        """Parse datetime from Socrata API"""
        if not date_str:
            return None
            
        # Remove timezone info and parse
        date_str = re.sub(r'T.*', '', str(date_str))
        
        try:
            return datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
            try:
                return datetime.strptime(date_str[:19], "%Y-%m-%dT%H:%M:%S")
            except ValueError:
                return None

    def categorize_issue(self, issue: EnvironmentalIssue) -> Optional[EventCategory]:
        """Intelligently categorize an issue into an event type"""
        text_to_check = f"{issue.complaint_type} {issue.descriptor}".lower()
        
        # Check each category mapping
        for category_name, mapping in self.ENVIRONMENTAL_MAPPINGS.items():
            # Check complaint types first (exact match)
            if issue.complaint_type in mapping["complaint_types"]:
                return mapping["category"]
                
            # Check keywords
            for keyword in mapping["keywords"]:
                if keyword in text_to_check:
                    return mapping["category"]
                    
        return None

    def generate_event_title(self, issues: List[EnvironmentalIssue], category: EventCategory) -> str:
        """Generate intelligent event title based on issues and category"""
        if not issues:
            return "Environmental Community Event"
            
        primary_issue = issues[0]
        area = self._extract_area_name(primary_issue.incident_address)
        
        # Get the most common complaint type
        complaint_types = [issue.complaint_type for issue in issues]
        most_common = max(set(complaint_types), key=complaint_types.count) if complaint_types else "Environmental"
        
        if category == EventCategory.cleanup:
            if "graffiti" in most_common.lower():
                return f"{area} Graffiti Removal & Beautification"
            elif "dumping" in most_common.lower():
                return f"{area} Illegal Dumping Cleanup"
            elif "litter" in most_common.lower() or "trash" in most_common.lower():
                return f"{area} Community Litter Cleanup"
            else:
                return f"{area} Environmental Cleanup Drive"
                
        elif category == EventCategory.advocacy:
            if "air" in most_common.lower():
                return f"{area} Air Quality Action Meeting"
            elif "noise" in most_common.lower():
                return f"{area} Noise Pollution Advocacy"
            elif "water" in most_common.lower():
                return f"{area} Water Quality Protection Rally"
            else:
                return f"{area} Environmental Justice Meeting"
                
        elif category == EventCategory.education:
            return f"{area} Environmental Awareness Workshop"
            
        return f"{area} Environmental Community Event"

    def generate_event_description(self, issues: List[EnvironmentalIssue], category: EventCategory) -> str:
        """Generate detailed, intelligent event description"""
        if not issues:
            return "Community environmental event addressing local concerns."
            
        primary_issue = issues[0]
        area = self._extract_area_name(primary_issue.incident_address)
        issue_count = len(issues)
        
        # Analyze issues for better description
        complaint_summary = self._analyze_complaints(issues)
        agency_focus = self._get_agency_focus(issues)
        
        description = f"Join us for a community environmental event in {area}! "
        
        if issue_count == 1:
            description += f"We're addressing a reported {primary_issue.complaint_type.lower()} issue. "
        else:
            description += f"We're tackling {issue_count} related environmental concerns in the area. "
            
        # Add specific issue details
        description += f"Issues include: {complaint_summary}"
        
        if primary_issue.descriptor:
            description += f" Specific concerns: {primary_issue.descriptor}"
            
        description += f"\n\n🎯 **Event Focus:** {agency_focus}\n"
        
        # Category-specific content
        if category == EventCategory.cleanup:
            description += "\n**What we'll do:**\n"
            description += "• Remove litter, debris, and illegal dumping\n"
            description += "• Clean and beautify public spaces\n"
            description += "• Proper waste sorting and disposal\n"
            description += "• Document before/after progress\n\n"
            description += "**What we provide:**\n"
            description += "• All cleanup supplies and safety equipment\n"
            description += "• Trash bags, gloves, and pickup tools\n"
            description += "• Refreshments and snacks\n"
            description += "• Community service hours documentation\n"
            
        elif category == EventCategory.advocacy:
            description += "\n**What we'll do:**\n"
            description += "• Discuss environmental concerns and impacts\n"
            description += "• Plan community advocacy strategies\n"
            description += "• Connect with local officials and agencies\n"
            description += "• Organize petition and awareness campaigns\n\n"
            description += "**What we provide:**\n"
            description += "• Expert speakers and community leaders\n"
            description += "• Information packets and resources\n"
            description += "• Action planning materials\n"
            description += "• Networking opportunities\n"
            
        elif category == EventCategory.education:
            description += "\n**What we'll learn:**\n"
            description += "• Environmental best practices and solutions\n"
            description += "• How to report and prevent future issues\n"
            description += "• Sustainable living and waste reduction\n"
            description += "• Community resources and programs\n\n"
            description += "**What we provide:**\n"
            description += "• Educational materials and workshops\n"
            description += "• Expert presentations\n"
            description += "• Take-home resources\n"
            description += "• Q&A with environmental specialists\n"
            
        description += f"\n🤖 *This event was automatically generated based on {issue_count} community-reported environmental concern(s). "
        description += "Together, we can make a real difference in our neighborhood!*"
        
        return description

    def _extract_area_name(self, address: str) -> str:
        """Extract neighborhood/area name from address"""
        if not address:
            return "Community"
            
        # Clean up address and extract meaningful area name
        address = address.strip()
        
        # Try to extract street name or area
        parts = address.split(",")
        if len(parts) > 1:
            return parts[0].strip()
        
        # Extract street name from full address
        words = address.split()
        if len(words) >= 2:
            # Look for street indicators
            street_indicators = ["ST", "STREET", "AVE", "AVENUE", "BLVD", "BOULEVARD", "RD", "ROAD", "DR", "DRIVE"]
            for i, word in enumerate(words):
                if word.upper() in street_indicators and i > 0:
                    return " ".join(words[max(0, i-2):i+1])
                    
        # Fallback to first few words
        return " ".join(words[:3]) if words else "Community"

    def _analyze_complaints(self, issues: List[EnvironmentalIssue]) -> str:
        """Analyze and summarize complaint types"""
        complaint_counts = {}
        for issue in issues:
            complaint_counts[issue.complaint_type] = complaint_counts.get(issue.complaint_type, 0) + 1
            
        # Get top 3 complaint types
        top_complaints = sorted(complaint_counts.items(), key=lambda x: x[1], reverse=True)[:3]
        
        if len(top_complaints) == 1:
            return top_complaints[0][0]
        elif len(top_complaints) == 2:
            return f"{top_complaints[0][0]} and {top_complaints[1][0]}"
        else:
            return f"{top_complaints[0][0]}, {top_complaints[1][0]}, and {top_complaints[2][0]}"

    def _get_agency_focus(self, issues: List[EnvironmentalIssue]) -> str:
        """Determine agency focus for event description"""
        agencies = [issue.agency for issue in issues if issue.agency]
        if not agencies:
            return "environmental improvement and community action"
            
        most_common_agency = max(set(agencies), key=agencies.count)
        return self.AGENCY_FOCUS.get(most_common_agency, "environmental protection and community safety")

    def cluster_nearby_issues(self, issues: List[EnvironmentalIssue], 
                            max_distance_km: float = 0.3) -> List[List[EnvironmentalIssue]]:
        """Group nearby issues for single events"""
        if not issues:
            return []
            
        clusters = []
        used_indices = set()
        
        for i, issue in enumerate(issues):
            if i in used_indices:
                continue
                
            cluster = [issue]
            used_indices.add(i)
            
            # Find nearby issues of similar type
            for j, other_issue in enumerate(issues):
                if j in used_indices or i == j:
                    continue
                    
                # Check distance
                distance = self._haversine_distance(
                    issue.lat, issue.lng,
                    other_issue.lat, other_issue.lng
                )
                
                # Check if similar issue type
                similar_type = (
                    issue.complaint_type == other_issue.complaint_type or
                    self.categorize_issue(issue) == self.categorize_issue(other_issue)
                )
                
                if distance <= max_distance_km and similar_type:
                    cluster.append(other_issue)
                    used_indices.add(j)
                    
            clusters.append(cluster)
            
        return clusters

    def _haversine_distance(self, lat1: float, lng1: float, 
                          lat2: float, lng2: float) -> float:
        """Calculate distance between two points in kilometers"""
        from math import radians, cos, sin, asin, sqrt
        
        lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
        
        dlat = lat2 - lat1
        dlng = lng2 - lng1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
        c = 2 * asin(sqrt(a))
        
        return c * 6371  # Earth's radius in km

    async def create_events_from_cluster(self, cluster: List[EnvironmentalIssue]) -> Optional[Event]:
        """Create an event from a cluster of related issues"""
        if not cluster:
            return None
            
        # Determine event category
        category = self.categorize_issue(cluster[0])
        if not category:
            category = EventCategory.cleanup  # Default
            
        # Calculate center point
        center_lat = sum(issue.lat for issue in cluster) / len(cluster)
        center_lng = sum(issue.lng for issue in cluster) / len(cluster)
        
        # Generate event details
        title = self.generate_event_title(cluster, category)
        description = self.generate_event_description(cluster, category)
        
        # Schedule event for next weekend
        now = datetime.now()
        days_until_saturday = (5 - now.weekday()) % 7
        if days_until_saturday == 0:
            days_until_saturday = 7
            
        event_start = now.replace(hour=10, minute=0, second=0, microsecond=0) + \
                     timedelta(days=days_until_saturday)
        event_end = event_start + timedelta(hours=3)
        
        try:
            # Create marker
            marker = AppMarker(
                id=uuid.uuid4(),
                type=MarkerType.event,
                latitude=center_lat,
                longitude=center_lng,
                created_by=uuid.uuid4(),
                created_at=datetime.now(),
                updated_at=datetime.now()
            )
            
            created_marker = SupabaseService.create_marker(marker)
            if not created_marker:
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
                max_participants=40 if category == EventCategory.cleanup else 25,
                current_participants=0,
                status=EventStatus.upcoming,
                created_at=datetime.now(),
                updated_at=datetime.now()
            )
            
            created_event = SupabaseService.create_event(event)
            if created_event:
                self.created_events_count += 1
                logger.info(f"✅ Created event: {created_event.title}")
                
            return created_event
            
        except Exception as e:
            logger.error(f"Failed to create event: {e}")
            return None

    async def scrape_city(self, city: SocrataConfig) -> List[Event]:
        """Scrape a single city and create events"""
        # Fetch 311 data
        issues = await self.fetch_311_data(city, days_back=14)
        
        if not issues:
            logger.info(f"No environmental issues found for {city.name}")
            return []
            
        logger.info(f"Found {len(issues)} environmental issues in {city.name}")
        self.processed_issues_count += len(issues)
        
        # Cluster nearby similar issues
        clusters = self.cluster_nearby_issues(issues)
        logger.info(f"Created {len(clusters)} issue clusters in {city.name}")
        
        # Create events from clusters
        created_events = []
        for cluster in clusters:
            if len(cluster) >= 1:  # Create events for single issues or clusters
                event = await self.create_events_from_cluster(cluster)
                if event:
                    created_events.append(event)
                    
                # Rate limiting
                await asyncio.sleep(city.rate_limit_delay)
                
        return created_events

    async def scrape_all_cities(self) -> Dict[str, List[Event]]:
        """Scrape all configured cities"""
        logger.info("🚀 Starting enhanced environmental event scraping...")
        
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
    print("🌍 Enhanced Environmental Event Scraper")
    print("=" * 50)
    
    async with EnhancedEventScraper() as scraper:
        results = await scraper.scrape_all_cities()
        
        total_events = sum(len(events) for events in results.values())
        
        print(f"\n📊 Enhanced Scraping Results:")
        print(f"Cities processed: {len(results)}")
        print(f"Total events created: {total_events}")
        print(f"Total issues processed: {scraper.processed_issues_count}")
        
        for city_name, events in results.items():
            if events:
                print(f"\n🏙️  {city_name}: {len(events)} events")
                for event in events[:3]:  # Show first 3 events per city
                    print(f"   • {event.title} ({event.category})")
            else:
                print(f"\n🏙️  {city_name}: 0 events")
            
        print(f"\n✨ Enhanced scraping completed!")
        if total_events > 0:
            print("🎉 Intelligent events created with proper categorization!")
            print("\n💡 Features:")
            print("• Smart event categorization (cleanup, advocacy, education)")
            print("• Detailed descriptions based on actual 311 data")
            print("• Geographic clustering of related issues")
            print("• Agency-specific event focus")
        else:
            print("⚠️  No events were created. Check your connection and try again.")


if __name__ == "__main__":
    asyncio.run(main())
