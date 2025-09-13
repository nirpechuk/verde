#!/usr/bin/env python3
"""
Boston Environmental Event Scraper

Focused scraper for Boston area environmental issues using Claude API
for highly customized event descriptions based on actual 311 data.

Data Source: Boston 311 Service Requests (Analyze Boston)
AI Integration: Claude API for dynamic content generation
"""

import asyncio
import aiohttp
import uuid
import csv
import os
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from dataclasses import dataclass
import json
import logging
from io import StringIO

from supabase_service import SupabaseService
from models import AppMarker, Event, MarkerType, EventCategory, EventStatus

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class BostonIssue:
    """Represents a Boston 311 environmental issue"""
    case_enquiry_id: str
    case_title: str
    subject: str
    reason: str
    type_value: str
    queue: str
    department: str
    submittedphoto: str
    closedphoto: str
    location: str
    fire_district: str
    pwd_district: str
    city_council_district: str
    police_district: str
    neighborhood: str
    ward: str
    precinct: str
    location_street_name: str
    location_zipcode: str
    latitude: float
    longitude: float
    source: str
    status: str
    closure_reason: str
    case_status: str
    closure_comment: str
    open_dt: datetime
    target_dt: Optional[datetime]
    closed_dt: Optional[datetime]


class BostonEventScraper:
    """Boston-focused scraper with Claude AI integration"""
    
    # Boston 311 data URL (most recent year)
    BOSTON_311_URL = "https://data.boston.gov/dataset/8048697b-ad64-4bfc-b090-ee00169f2323/resource/9d7c2214-4709-478a-a2e8-fb2020a5bb94/download/tmp9tlmmpc1.csv"
    
    # Environmental issue mappings specific to Boston 311 data
    ENVIRONMENTAL_CATEGORIES = {
        # Cleanup events
        EventCategory.cleanup: {
            "subjects": [
                "Graffiti", "Illegal Dumping", "Litter", "Trash", "Garbage", 
                "Abandoned Bicycle", "Abandoned Vehicle", "Street Cleaning",
                "Sidewalk Cleaning", "Park Maintenance", "Dead Animal",
                "Bulk Item Pickup", "Mattress", "Furniture", "Construction Debris",
                "Overflowing Litter Baskets", "Dirty Conditions", "Sanitation"
            ],
            "reasons": [
                "Illegal Dumping", "Litter Basket / Request", "Graffiti Removal",
                "Street/Sidewalk", "Sanitation Condition", "Overflowing Basket",
                "Bulk Item", "Dead Animal Removal", "Park Cleaning"
            ],
            "departments": ["PWD", "Parks & Recreation Department", "Public Works"]
        },
        
        # Advocacy events
        EventCategory.advocacy: {
            "subjects": [
                "Air Pollution Complaint", "Noise Disturbance", "Water Quality",
                "Environmental Services", "Hazardous Material", "Chemical Spill",
                "Industrial Waste", "Sewage", "Storm Drain", "Odor Complaint",
                "Toxic Material", "Environmental Violation"
            ],
            "reasons": [
                "Air Quality", "Noise", "Water Quality", "Environmental",
                "Hazmat", "Chemical", "Industrial", "Pollution", "Toxic",
                "Sewage Backup", "Illegal Discharge"
            ],
            "departments": ["Environment Department", "ISD", "BWSC"]
        },
        
        # Education events  
        EventCategory.education: {
            "subjects": [
                "Recycling", "Composting", "Green Program", "Sustainability",
                "Energy Conservation", "Environmental Education", "Outreach"
            ],
            "reasons": [
                "Recycling Request", "Composting Program", "Green Initiative",
                "Energy Program", "Environmental Awareness"
            ],
            "departments": ["Environment Department", "Mayor's Office"]
        }
    }
    
    # Claude API configuration
    CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
    
    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None
        self.created_events_count = 0
        self.processed_issues_count = 0
        self.claude_api_key = os.getenv("CLAUDE_API_KEY")
        
        if not self.claude_api_key:
            logger.warning("CLAUDE_API_KEY not found in environment variables")

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=120),
            headers={'User-Agent': 'Boston-Environmental-Scraper/1.0'}
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def fetch_boston_311_data(self, days_back: int = 14) -> List[BostonIssue]:
        """Fetch Boston 311 data from CSV"""
        logger.info("🏛️ Fetching Boston 311 data...")
        
        try:
            async with self.session.get(self.BOSTON_311_URL) as response:
                if response.status != 200:
                    logger.error(f"Failed to fetch Boston data: {response.status}")
                    return []
                    
                csv_content = await response.text()
                logger.info(f"📄 Fetched CSV data: {len(csv_content)} characters")
                
                # Debug: Show first few lines of CSV
                lines = csv_content.split('\n')[:5]
                logger.info(f"📋 CSV header and sample: {lines}")
                
                return self._parse_boston_csv(csv_content, days_back)
                
        except Exception as e:
            logger.error(f"Error fetching Boston data: {e}")
            return []

    def _parse_boston_csv(self, csv_content: str, days_back: int) -> List[BostonIssue]:
        """Parse Boston 311 CSV data"""
        issues = []
        cutoff_date = datetime.now() - timedelta(days=days_back)
        
        try:
            csv_reader = csv.DictReader(StringIO(csv_content))
            
            total_rows = 0
            date_filtered = 0
            env_filtered = 0
            coord_filtered = 0
            
            for row in csv_reader:
                total_rows += 1
                
                # Debug: Show first few rows
                if total_rows <= 3:
                    logger.info(f"📝 Row {total_rows} keys: {list(row.keys())}")
                    logger.info(f"📝 Row {total_rows} sample data: Subject={row.get('Subject')}, open_dt={row.get('open_dt')}")
                
                try:
                    # Parse dates
                    open_dt = self._parse_boston_date(row.get('open_dt', ''))
                    if not open_dt or open_dt < cutoff_date:
                        date_filtered += 1
                        continue
                        
                    # Check if environmental issue
                    if not self._is_environmental_issue(row):
                        env_filtered += 1
                        continue
                        
                    # Parse coordinates
                    lat = self._safe_float(row.get('Latitude'))
                    lng = self._safe_float(row.get('Longitude'))
                    
                    if not lat or not lng:
                        coord_filtered += 1
                        continue
                        
                    target_dt = self._parse_boston_date(row.get('target_dt', ''))
                    closed_dt = self._parse_boston_date(row.get('closed_dt', ''))
                    
                    issue = BostonIssue(
                        case_enquiry_id=row.get('case_enquiry_id', ''),
                        case_title=row.get('case_title', ''),
                        subject=row.get('Subject', ''),
                        reason=row.get('Reason', ''),
                        type_value=row.get('TYPE', ''),
                        queue=row.get('queue', ''),
                        department=row.get('Department', ''),
                        submittedphoto=row.get('SubmittedPhoto', ''),
                        closedphoto=row.get('ClosedPhoto', ''),
                        location=row.get('Location', ''),
                        fire_district=row.get('Fire_district', ''),
                        pwd_district=row.get('pwd_district', ''),
                        city_council_district=row.get('city_council_district', ''),
                        police_district=row.get('police_district', ''),
                        neighborhood=row.get('neighborhood', ''),
                        ward=row.get('ward', ''),
                        precinct=row.get('precinct', ''),
                        location_street_name=row.get('Location_Street_Name', ''),
                        location_zipcode=row.get('Location_zipcode', ''),
                        latitude=lat,
                        longitude=lng,
                        source=row.get('Source', ''),
                        status=row.get('Status', ''),
                        closure_reason=row.get('closure_reason', ''),
                        case_status=row.get('case_status', ''),
                        closure_comment=row.get('closure_comment', ''),
                        open_dt=open_dt,
                        target_dt=target_dt,
                        closed_dt=closed_dt
                    )
                    
                    issues.append(issue)
                    
                except Exception as e:
                    logger.debug(f"Skipping malformed row: {e}")
                    continue
                    
            logger.info(f"📊 CSV Processing Summary:")
            logger.info(f"  Total rows processed: {total_rows}")
            logger.info(f"  Filtered by date: {date_filtered}")
            logger.info(f"  Filtered by environmental criteria: {env_filtered}")
            logger.info(f"  Filtered by missing coordinates: {coord_filtered}")
            logger.info(f"  Final environmental issues: {len(issues)}")
                    
        except Exception as e:
            logger.error(f"Error parsing CSV: {e}")
            
        return issues

    def _parse_boston_date(self, date_str: str) -> Optional[datetime]:
        """Parse Boston 311 date format"""
        if not date_str or date_str.strip() == '':
            return None
            
        try:
            # Try different date formats used in Boston data
            formats = [
                "%Y-%m-%d %H:%M:%S",
                "%m/%d/%Y %H:%M:%S %p",
                "%m/%d/%Y %H:%M:%S",
                "%Y-%m-%d",
                "%m/%d/%Y"
            ]
            
            for fmt in formats:
                try:
                    return datetime.strptime(date_str.strip(), fmt)
                except ValueError:
                    continue
                    
        except Exception:
            pass
            
        return None

    def _safe_float(self, value) -> Optional[float]:
        """Safely convert to float"""
        if not value or str(value).strip() == '':
            return None
        try:
            return float(value)
        except (ValueError, TypeError):
            return None

    def _is_environmental_issue(self, row: Dict) -> bool:
        """Check if a Boston 311 issue is environmental"""
        subject = (row.get('Subject', '') or '').lower()
        reason = (row.get('Reason', '') or '').lower()
        department = (row.get('Department', '') or '').lower()
        
        # Debug: Log what we're checking
        if subject or reason or department:
            logger.debug(f"🔍 Checking: Subject='{subject}', Reason='{reason}', Dept='{department}'")
        
        # Check against all environmental categories
        for category_data in self.ENVIRONMENTAL_CATEGORIES.values():
            # Check subjects
            for env_subject in category_data['subjects']:
                if env_subject.lower() in subject:
                    logger.debug(f"✅ Found environmental match in subject: {env_subject}")
                    return True
                    
            # Check reasons
            for env_reason in category_data['reasons']:
                if env_reason.lower() in reason:
                    logger.debug(f"✅ Found environmental match in reason: {env_reason}")
                    return True
                    
            # Check departments
            for env_dept in category_data['departments']:
                if env_dept.lower() in department:
                    logger.debug(f"✅ Found environmental match in department: {env_dept}")
                    return True
                    
        return False

    def categorize_boston_issue(self, issue: BostonIssue) -> EventCategory:
        """Categorize Boston issue into event type"""
        subject = issue.subject.lower()
        reason = issue.reason.lower()
        department = issue.department.lower()
        
        # Check each category
        for category, data in self.ENVIRONMENTAL_CATEGORIES.items():
            # Check subjects first
            for env_subject in data['subjects']:
                if env_subject.lower() in subject:
                    return category
                    
            # Check reasons
            for env_reason in data['reasons']:
                if env_reason.lower() in reason:
                    return category
                    
            # Check departments
            for env_dept in data['departments']:
                if env_dept.lower() in department:
                    return category
                    
        # Default to cleanup
        return EventCategory.cleanup

    async def generate_claude_content(self, issues: List[BostonIssue], category: EventCategory) -> Dict[str, str]:
        """Generate event title and description using Claude API"""
        if not self.claude_api_key:
            return self._generate_fallback_content(issues, category)
            
        # Prepare issue data for Claude
        issue_data = []
        for issue in issues:
            issue_info = {
                "subject": issue.subject,
                "reason": issue.reason,
                "department": issue.department,
                "neighborhood": issue.neighborhood,
                "status": issue.status,
                "case_title": issue.case_title
            }
            if issue.closure_comment:
                issue_info["closure_comment"] = issue.closure_comment
            issue_data.append(issue_info)
            
        # Create prompt for Claude
        prompt = self._create_claude_prompt(issue_data, category)
        
        try:
            headers = {
                "Content-Type": "application/json",
                "x-api-key": self.claude_api_key,
                "anthropic-version": "2023-06-01"
            }
            
            payload = {
                "model": "claude-3-haiku-20240307",
                "max_tokens": 1000,
                "messages": [
                    {
                        "role": "user",
                        "content": prompt
                    }
                ]
            }
            
            async with self.session.post(self.CLAUDE_API_URL, headers=headers, json=payload) as response:
                if response.status == 200:
                    result = await response.json()
                    content = result["content"][0]["text"]
                    return self._parse_claude_response(content)
                else:
                    logger.warning(f"Claude API failed: {response.status}")
                    return self._generate_fallback_content(issues, category)
                    
        except Exception as e:
            logger.error(f"Error calling Claude API: {e}")
            return self._generate_fallback_content(issues, category)

    def _create_claude_prompt(self, issue_data: List[Dict], category: EventCategory) -> str:
        """Create prompt for Claude API"""
        category_name = category.value
        issue_count = len(issue_data)
        
        prompt = f"""You are creating a community environmental event based on real Boston 311 service requests. 

IMPORTANT RULES:
- Do NOT include addresses, street names, or specific locations in the title or description
- The address is displayed separately in the app
- Focus on the type of environmental issue and community action needed
- Make it engaging and actionable for volunteers

Event Category: {category_name}
Number of related issues: {issue_count}

Issue Details:
"""
        
        for i, issue in enumerate(issue_data[:3], 1):  # Limit to first 3 issues
            prompt += f"\nIssue {i}:\n"
            prompt += f"- Subject: {issue['subject']}\n"
            prompt += f"- Reason: {issue['reason']}\n"
            prompt += f"- Department: {issue['department']}\n"
            prompt += f"- Neighborhood: {issue['neighborhood']}\n"
            if issue.get('case_title'):
                prompt += f"- Case Title: {issue['case_title']}\n"
                
        prompt += f"""

Please generate:
1. A compelling event title (no addresses/locations)
2. A detailed event description that explains what volunteers will do

Format your response as:
TITLE: [event title here]
DESCRIPTION: [event description here]

The description should include:
- What the environmental issue is
- What volunteers will accomplish  
- What supplies/support will be provided
- Why this matters to the community
- Call to action for participation

Keep it professional but engaging, around 200-300 words."""

        return prompt

    def _parse_claude_response(self, content: str) -> Dict[str, str]:
        """Parse Claude's response into title and description"""
        try:
            lines = content.strip().split('\n')
            title = ""
            description = ""
            
            current_section = None
            for line in lines:
                line = line.strip()
                if line.startswith("TITLE:"):
                    title = line.replace("TITLE:", "").strip()
                    current_section = "title"
                elif line.startswith("DESCRIPTION:"):
                    description = line.replace("DESCRIPTION:", "").strip()
                    current_section = "description"
                elif current_section == "description" and line:
                    description += " " + line
                    
            return {
                "title": title or "Community Environmental Action",
                "description": description or "Join us for environmental community action in Boston."
            }
            
        except Exception as e:
            logger.error(f"Error parsing Claude response: {e}")
            return {
                "title": "Community Environmental Action",
                "description": "Join us for environmental community action in Boston."
            }

    def _generate_fallback_content(self, issues: List[BostonIssue], category: EventCategory) -> Dict[str, str]:
        """Generate fallback content when Claude API is unavailable"""
        primary_issue = issues[0]
        issue_count = len(issues)
        
        # Generate title based on category and issue type
        if category == EventCategory.cleanup:
            if "graffiti" in primary_issue.subject.lower():
                title = "Community Graffiti Removal Event"
            elif "dumping" in primary_issue.subject.lower():
                title = "Illegal Dumping Cleanup Drive"
            elif "litter" in primary_issue.subject.lower():
                title = "Neighborhood Litter Cleanup"
            else:
                title = "Environmental Cleanup Event"
        elif category == EventCategory.advocacy:
            if "air" in primary_issue.subject.lower():
                title = "Air Quality Community Meeting"
            elif "noise" in primary_issue.subject.lower():
                title = "Noise Pollution Action Group"
            else:
                title = "Environmental Advocacy Meeting"
        else:
            title = "Environmental Education Workshop"
            
        # Generate description
        description = f"Join us for a community environmental event addressing {primary_issue.subject.lower()} concerns. "
        
        if issue_count > 1:
            description += f"We're tackling {issue_count} related environmental issues reported to Boston 311. "
        else:
            description += "This event addresses a specific environmental concern reported to Boston 311. "
            
        description += f"The {primary_issue.department} department has been notified, and community action can help accelerate solutions.\n\n"
        
        if category == EventCategory.cleanup:
            description += "What we'll provide:\n• All cleanup supplies and safety equipment\n• Waste disposal coordination\n• Refreshments for volunteers\n• Community service documentation\n\n"
        elif category == EventCategory.advocacy:
            description += "What we'll do:\n• Discuss the environmental concerns\n• Plan community advocacy strategies\n• Connect with city officials\n• Organize follow-up actions\n\n"
        else:
            description += "What you'll learn:\n• Environmental best practices\n• How to report issues effectively\n• Community resources available\n• Prevention strategies\n\n"
            
        description += "Together, we can make a real difference in our Boston neighborhoods!"
        
        return {"title": title, "description": description}

    def cluster_nearby_issues(self, issues: List[BostonIssue], max_distance_km: float = 0.2) -> List[List[BostonIssue]]:
        """Cluster nearby Boston issues"""
        if not issues:
            return []
            
        clusters = []
        used_indices = set()
        
        for i, issue in enumerate(issues):
            if i in used_indices:
                continue
                
            cluster = [issue]
            used_indices.add(i)
            
            # Find nearby issues of similar category
            issue_category = self.categorize_boston_issue(issue)
            
            for j, other_issue in enumerate(issues):
                if j in used_indices or i == j:
                    continue
                    
                # Check if same category
                other_category = self.categorize_boston_issue(other_issue)
                if issue_category != other_category:
                    continue
                    
                # Check distance
                distance = self._haversine_distance(
                    issue.latitude, issue.longitude,
                    other_issue.latitude, other_issue.longitude
                )
                
                if distance <= max_distance_km:
                    cluster.append(other_issue)
                    used_indices.add(j)
                    
            clusters.append(cluster)
            
        return clusters

    def _haversine_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """Calculate distance between two points in kilometers"""
        from math import radians, cos, sin, asin, sqrt
        
        lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
        
        dlat = lat2 - lat1
        dlng = lng2 - lng1
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
        c = 2 * asin(sqrt(a))
        
        return c * 6371

    async def create_event_from_cluster(self, cluster: List[BostonIssue]) -> Optional[Event]:
        """Create event from Boston issue cluster"""
        if not cluster:
            return None
            
        # Determine category
        category = self.categorize_boston_issue(cluster[0])
        
        # Calculate center point
        center_lat = sum(issue.latitude for issue in cluster) / len(cluster)
        center_lng = sum(issue.longitude for issue in cluster) / len(cluster)
        
        # Generate content using Claude API
        content = await self.generate_claude_content(cluster, category)
        
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
                title=content["title"],
                description=content["description"],
                category=category,
                start_time=event_start,
                end_time=event_end,
                max_participants=35 if category == EventCategory.cleanup else 20,
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

    async def scrape_boston(self) -> List[Event]:
        """Main scraping function for Boston"""
        logger.info("🏛️ Starting Boston environmental event scraping...")
        
        # Fetch Boston 311 data
        issues = await self.fetch_boston_311_data(days_back=21)  # 3 weeks of data
        
        if not issues:
            logger.info("No environmental issues found in Boston data")
            return []
            
        logger.info(f"Found {len(issues)} environmental issues in Boston")
        self.processed_issues_count = len(issues)
        
        # Cluster nearby similar issues
        clusters = self.cluster_nearby_issues(issues)
        logger.info(f"Created {len(clusters)} issue clusters")
        
        # Create events from clusters
        created_events = []
        for cluster in clusters:
            if len(cluster) >= 1:
                event = await self.create_event_from_cluster(cluster)
                if event:
                    created_events.append(event)
                    
                # Rate limiting for API calls
                await asyncio.sleep(1.0)
                
        return created_events


async def main():
    """Main function"""
    print("🏛️ Boston Environmental Event Scraper")
    print("=" * 50)
    
    async with BostonEventScraper() as scraper:
        events = await scraper.scrape_boston()
        
        print(f"\n📊 Boston Scraping Results:")
        print(f"Environmental issues processed: {scraper.processed_issues_count}")
        print(f"Events created: {len(events)}")
        
        if events:
            print(f"\n🎉 Created Events:")
            for event in events:
                print(f"  • {event.title} ({event.category})")
                print(f"    {event.description[:100]}...")
                print()
                
            print("✨ Boston events created successfully!")
            print("Check your Supabase dashboard to see the detailed events.")
        else:
            print("⚠️  No events were created. Check your data source and API keys.")


if __name__ == "__main__":
    asyncio.run(main())
