-- Event-Issue linking patch for EcoAction database
-- Run this in your Supabase SQL editor to add event-issue linking support

-- Add issue_id column to events table if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'events' AND column_name = 'issue_id'
    ) THEN
        ALTER TABLE events ADD COLUMN issue_id UUID REFERENCES issues(id) ON DELETE SET NULL;
    END IF;
END $$;

-- Create index for better performance on issue_id lookups
CREATE INDEX IF NOT EXISTS idx_events_issue_id ON events (issue_id);

-- Add a function to get events linked to an issue
CREATE OR REPLACE FUNCTION get_events_for_issue(p_issue_id UUID)
RETURNS TABLE (
    id UUID,
    marker_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE,
    max_participants INTEGER,
    current_participants INTEGER,
    status TEXT,
    image_url TEXT,
    issue_id UUID,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id,
        e.marker_id,
        e.title,
        e.description,
        e.category,
        e.start_time,
        e.end_time,
        e.max_participants,
        e.current_participants,
        e.status,
        e.image_url,
        e.issue_id,
        e.created_at,
        e.updated_at
    FROM events e
    WHERE e.issue_id = p_issue_id
    ORDER BY e.start_time ASC;
END;
$$ LANGUAGE plpgsql;

-- Add RLS policy for linked events
CREATE POLICY IF NOT EXISTS "Public linked events are viewable" ON events 
FOR SELECT USING (issue_id IS NOT NULL OR issue_id IS NULL);

-- Update the existing events view policy to include issue_id
DROP POLICY IF EXISTS "Public events are viewable by everyone" ON events;
CREATE POLICY "Public events are viewable by everyone" ON events 
FOR SELECT USING (true);
