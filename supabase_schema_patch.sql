-- Patch script for existing EcoAction database
-- Run this to fix foreign key constraint and RLS policy issues

-- Add RLS policy for user creation (if not exists)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'users' AND policyname = 'Users can create their own profile'
    ) THEN
        CREATE POLICY "Users can create their own profile" ON users FOR INSERT WITH CHECK (auth.uid() = id);
    END IF;
END $$;

-- Add RLS policy for user points history (if not exists)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'user_points_history' AND policyname = 'Users can create their own points history'
    ) THEN
        CREATE POLICY "Users can create their own points history" ON user_points_history FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

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

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trigger_ensure_user_exists ON markers;
CREATE TRIGGER trigger_ensure_user_exists
    BEFORE INSERT ON markers
    FOR EACH ROW
    EXECUTE FUNCTION ensure_user_exists();

-- Update award_points function to ensure user exists
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
