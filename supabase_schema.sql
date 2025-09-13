-- Environmental Crowdsourcing Platform Database Schema
-- Run this in your Supabase SQL editor

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table for tracking points and profile
CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    email TEXT UNIQUE,
    username TEXT UNIQUE,
    points INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Markers table (parent table for issues and events)
CREATE TABLE markers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('issue', 'event')),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location GEOGRAPHY(POINT, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)) STORED,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Issues table (red markers)
CREATE TABLE issues (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    marker_id UUID REFERENCES markers(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('trash', 'water_pollution', 'air_pollution', 'noise_pollution', 'other')),
    image_url TEXT,
    credibility_score INTEGER DEFAULT 0,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'removed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Events table (green markers)
CREATE TABLE events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    marker_id UUID REFERENCES markers(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('cleanup', 'advocacy', 'education', 'other')),
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    max_participants INTEGER,
    current_participants INTEGER DEFAULT 0,
    status TEXT DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'active', 'completed', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Issue votes for credibility system
CREATE TABLE issue_votes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    issue_id UUID REFERENCES issues(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    vote INTEGER CHECK (vote IN (-1, 1)), -- -1 for downvote, 1 for upvote
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(issue_id, user_id)
);

-- Event RSVPs
CREATE TABLE event_rsvps (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    event_id UUID REFERENCES events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    status TEXT DEFAULT 'going' CHECK (status IN ('going', 'maybe', 'not_going')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(event_id, user_id)
);

-- User points history for tracking actions
CREATE TABLE user_points_history (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    action_type TEXT NOT NULL CHECK (action_type IN ('report_issue', 'create_event', 'rsvp_event', 'vote_issue')),
    points INTEGER NOT NULL,
    reference_id UUID, -- Can reference issue_id, event_id, etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_markers_location ON markers USING GIST (location);
CREATE INDEX idx_markers_type ON markers (type);
CREATE INDEX idx_issues_status ON issues (status);
CREATE INDEX idx_events_status ON events (status);
CREATE INDEX idx_events_time ON events (start_time, end_time);

-- Functions to update credibility score when votes are added/removed
CREATE OR REPLACE FUNCTION update_issue_credibility()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE issues 
    SET credibility_score = (
        SELECT COALESCE(SUM(vote), 0) 
        FROM issue_votes 
        WHERE issue_id = COALESCE(NEW.issue_id, OLD.issue_id)
    )
    WHERE id = COALESCE(NEW.issue_id, OLD.issue_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger for updating credibility score
CREATE TRIGGER trigger_update_issue_credibility
    AFTER INSERT OR UPDATE OR DELETE ON issue_votes
    FOR EACH ROW
    EXECUTE FUNCTION update_issue_credibility();

-- Function to update event participant count
CREATE OR REPLACE FUNCTION update_event_participants()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE events 
    SET current_participants = (
        SELECT COUNT(*) 
        FROM event_rsvps 
        WHERE event_id = COALESCE(NEW.event_id, OLD.event_id) 
        AND status = 'going'
    )
    WHERE id = COALESCE(NEW.event_id, OLD.event_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger for updating participant count
CREATE TRIGGER trigger_update_event_participants
    AFTER INSERT OR UPDATE OR DELETE ON event_rsvps
    FOR EACH ROW
    EXECUTE FUNCTION update_event_participants();

-- Function to ensure user exists and award points
CREATE OR REPLACE FUNCTION award_points(
    p_user_id UUID,
    p_action_type TEXT,
    p_points INTEGER,
    p_reference_id UUID DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    -- Ensure user exists (create if not)
    INSERT INTO users (id, points) 
    VALUES (p_user_id, 0) 
    ON CONFLICT (id) DO NOTHING;
    
    -- Insert into points history
    INSERT INTO user_points_history (user_id, action_type, points, reference_id)
    VALUES (p_user_id, p_action_type, p_points, p_reference_id);
    
    -- Update user total points
    UPDATE users 
    SET points = points + p_points,
        updated_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to ensure user exists before creating markers
CREATE OR REPLACE FUNCTION ensure_user_exists()
RETURNS TRIGGER AS $$
BEGIN
    -- Create user if doesn't exist
    INSERT INTO users (id, points)
    VALUES (NEW.created_by, 0)
    ON CONFLICT (id) DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to ensure user exists before marker creation
CREATE TRIGGER trigger_ensure_user_exists
    BEFORE INSERT ON markers
    FOR EACH ROW
    EXECUTE FUNCTION ensure_user_exists();

-- Row Level Security (RLS) policies
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE markers ENABLE ROW LEVEL SECURITY;
ALTER TABLE issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE issue_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_rsvps ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_points_history ENABLE ROW LEVEL SECURITY;

-- Allow users to read all public data
CREATE POLICY "Public markers are viewable by everyone" ON markers FOR SELECT USING (true);
CREATE POLICY "Public issues are viewable by everyone" ON issues FOR SELECT USING (true);
CREATE POLICY "Public events are viewable by everyone" ON events FOR SELECT USING (true);

-- Allow authenticated users to insert their own data
CREATE POLICY "Users can insert their own markers" ON markers FOR INSERT WITH CHECK (auth.uid() = created_by);
CREATE POLICY "Users can insert their own issues" ON issues FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM markers WHERE id = marker_id AND created_by = auth.uid())
);
CREATE POLICY "Users can insert their own events" ON events FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM markers WHERE id = marker_id AND created_by = auth.uid())
);

-- Allow users to vote and RSVP
CREATE POLICY "Users can manage their own votes" ON issue_votes FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own RSVPs" ON event_rsvps FOR ALL USING (auth.uid() = user_id);

-- Allow users to view and create their own data
CREATE POLICY "Users can view their own profile" ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can create their own profile" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can view their own points history" ON user_points_history FOR SELECT USING (auth.uid() = user_id);
