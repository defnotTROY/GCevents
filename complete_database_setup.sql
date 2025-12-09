
-- ==========================================
-- START OF supabase_events_setup.sql
-- ==========================================

-- Create events table
CREATE TABLE IF NOT EXISTS events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  date DATE,
  time VARCHAR(50),
  location VARCHAR(255),
  max_participants INTEGER,
  category VARCHAR(100),
  status VARCHAR(50) DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'ongoing', 'completed', 'cancelled')),
  image_url TEXT,
  is_virtual BOOLEAN DEFAULT FALSE,
  virtual_link TEXT,
  requirements TEXT,
  contact_email VARCHAR(255),
  contact_phone VARCHAR(50),
  tags TEXT[], -- Array of tags
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create participants table
CREATE TABLE IF NOT EXISTS participants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  registration_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  status VARCHAR(50) DEFAULT 'registered' CHECK (status IN ('registered', 'attended', 'cancelled')),
  UNIQUE(event_id, user_id) -- Prevent duplicate registrations
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_events_user_id ON events(user_id);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_date ON events(date);
CREATE INDEX IF NOT EXISTS idx_participants_event_id ON participants(event_id);
CREATE INDEX IF NOT EXISTS idx_participants_user_id ON participants(user_id);

-- Enable Row Level Security (RLS)
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for events table
CREATE POLICY "Users can view their own events" ON events
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own events" ON events
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own events" ON events
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own events" ON events
  FOR DELETE USING (auth.uid() = user_id);

-- Create RLS policies for participants table
CREATE POLICY "Users can view participants of their events" ON participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = participants.event_id 
      AND events.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can register for events" ON participants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own registrations" ON participants
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own registrations" ON participants
  FOR DELETE USING (auth.uid() = user_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_events_updated_at 
  BEFORE UPDATE ON events 
  FOR EACH ROW 
  EXECUTE FUNCTION update_updated_at_column();

-- Sample events will be created when users sign up and create events through the app
-- The auth.uid() function only works when a user is authenticated
-- To test the functionality, create events through the EventCreation page in your app



-- ==========================================
-- START OF supabase_tickets_setup.sql
-- ==========================================

-- Tickets Table
CREATE TABLE IF NOT EXISTS tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  ticket_type VARCHAR(100) NOT NULL, -- e.g., 'General Admission', 'VIP', 'Early Bird', 'Student'
  name VARCHAR(255) NOT NULL, -- Display name
  description TEXT, -- Description of what's included
  price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  currency VARCHAR(10) DEFAULT 'USD',
  quantity INTEGER, -- Total quantity available (NULL = unlimited)
  sold INTEGER DEFAULT 0, -- Number of tickets sold
  available INTEGER, -- Calculated: quantity - sold (NULL if quantity is NULL)
  min_per_order INTEGER DEFAULT 1, -- Minimum tickets per order
  max_per_order INTEGER, -- Maximum tickets per order (NULL = unlimited)
  sale_start_date TIMESTAMPTZ, -- When ticket sales start
  sale_end_date TIMESTAMPTZ, -- When ticket sales end
  is_active BOOLEAN DEFAULT TRUE, -- Whether this ticket type is currently available
  is_visible BOOLEAN DEFAULT TRUE, -- Whether to show this ticket type publicly
  sort_order INTEGER DEFAULT 0, -- Order in which tickets are displayed
  metadata JSONB DEFAULT '{}', -- Additional metadata (e.g., access level, benefits)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_tickets_event_id ON tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_is_active ON tickets(is_active);
CREATE INDEX IF NOT EXISTS idx_tickets_is_visible ON tickets(is_visible);
CREATE INDEX IF NOT EXISTS idx_tickets_sale_dates ON tickets(sale_start_date, sale_end_date);

-- Ticket Purchases/Orders Table
CREATE TABLE IF NOT EXISTS ticket_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_price DECIMAL(10, 2) NOT NULL, -- Price at time of purchase
  total_price DECIMAL(10, 2) NOT NULL, -- quantity * unit_price
  currency VARCHAR(10) DEFAULT 'USD',
  order_number VARCHAR(50) UNIQUE, -- Unique order number
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled', 'refunded')),
  payment_status VARCHAR(50) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
  payment_method VARCHAR(50), -- 'credit_card', 'paypal', 'stripe', 'free', etc.
  payment_transaction_id VARCHAR(255), -- External payment transaction ID
  metadata JSONB DEFAULT '{}', -- Additional order metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for ticket orders
CREATE INDEX IF NOT EXISTS idx_ticket_orders_event_id ON ticket_orders(event_id);
CREATE INDEX IF NOT EXISTS idx_ticket_orders_user_id ON ticket_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_ticket_orders_ticket_id ON ticket_orders(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_orders_status ON ticket_orders(status);
CREATE INDEX IF NOT EXISTS idx_ticket_orders_payment_status ON ticket_orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_ticket_orders_order_number ON ticket_orders(order_number);

-- Function to generate unique order number
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TEXT AS $$
DECLARE
  new_order_number TEXT;
BEGIN
  LOOP
    new_order_number := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
                        LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM ticket_orders WHERE order_number = new_order_number);
  END LOOP;
  RETURN new_order_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update ticket sold count when order is completed
CREATE OR REPLACE FUNCTION update_ticket_sold_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    UPDATE tickets
    SET sold = sold + NEW.quantity,
        available = CASE 
          WHEN quantity IS NOT NULL THEN quantity - (sold + NEW.quantity)
          ELSE NULL
        END,
        updated_at = NOW()
    WHERE id = NEW.ticket_id;
  ELSIF NEW.status != 'completed' AND OLD.status = 'completed' THEN
    -- If order is cancelled/refunded, decrease sold count
    UPDATE tickets
    SET sold = GREATEST(0, sold - OLD.quantity),
        available = CASE 
          WHEN quantity IS NOT NULL THEN quantity - GREATEST(0, sold - OLD.quantity)
          ELSE NULL
        END,
        updated_at = NOW()
    WHERE id = OLD.ticket_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update ticket sold count
CREATE TRIGGER update_ticket_sold_on_order_status
  AFTER UPDATE OF status ON ticket_orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION update_ticket_sold_count();

-- Function to calculate available tickets
CREATE OR REPLACE FUNCTION calculate_ticket_availability()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.quantity IS NOT NULL THEN
    NEW.available = NEW.quantity - COALESCE(NEW.sold, 0);
  ELSE
    NEW.available = NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to calculate available tickets
CREATE TRIGGER calculate_ticket_availability_trigger
  BEFORE INSERT OR UPDATE ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION calculate_ticket_availability();

-- Enable Row Level Security (RLS)
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_orders ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tickets
CREATE POLICY "Anyone can view active tickets for public events"
  ON tickets FOR SELECT
  USING (
    is_visible = TRUE AND
    is_active = TRUE AND
    (sale_start_date IS NULL OR sale_start_date <= NOW()) AND
    (sale_end_date IS NULL OR sale_end_date >= NOW()) AND
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = tickets.event_id 
      AND events.status IN ('published', 'upcoming')
    )
  );

CREATE POLICY "Event organizers can view all tickets for their events"
  ON tickets FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = tickets.event_id 
      AND events.user_id = auth.uid()
    )
  );

CREATE POLICY "Event organizers can manage tickets for their events"
  ON tickets FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = tickets.event_id 
      AND events.user_id = auth.uid()
    )
  );

-- RLS Policies for ticket orders
CREATE POLICY "Users can view their own ticket orders"
  ON ticket_orders FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Event organizers can view all orders for their events"
  ON ticket_orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = ticket_orders.event_id 
      AND events.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create ticket orders"
  ON ticket_orders FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own ticket orders"
  ON ticket_orders FOR UPDATE
  USING (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE TRIGGER update_tickets_updated_at
  BEFORE UPDATE ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_ticket_orders_updated_at
  BEFORE UPDATE ON ticket_orders
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();




-- ==========================================
-- START OF supabase_verification_setup.sql
-- ==========================================

-- User Verifications Table
-- Stores verification documents and status for ethical event registration
CREATE TABLE IF NOT EXISTS user_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  verification_type VARCHAR(50) NOT NULL DEFAULT 'identity', -- 'identity', 'organization', 'student', 'professional', 'other'
  document_type VARCHAR(50) NOT NULL, -- 'id_card', 'passport', 'driver_license', 'student_id', 'organization_certificate', 'other'
  document_name VARCHAR(255) NOT NULL, -- Original filename
  file_path TEXT NOT NULL, -- Path to uploaded file in storage
  file_url TEXT NOT NULL, -- Public URL of the file
  file_size INTEGER, -- File size in bytes
  mime_type VARCHAR(100), -- File MIME type
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'expired')),
  reviewed_by UUID REFERENCES auth.users(id), -- Admin who reviewed
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT, -- Reason for rejection if rejected
  admin_notes TEXT, -- Internal notes for admins
  notification_sent BOOLEAN DEFAULT FALSE, -- Whether notification was sent to user
  expires_at TIMESTAMPTZ, -- When verification expires (if applicable)
  metadata JSONB DEFAULT '{}', -- Additional metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_user_verifications_user_id ON user_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_user_verifications_status ON user_verifications(status);
CREATE INDEX IF NOT EXISTS idx_user_verifications_reviewed_by ON user_verifications(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_user_verifications_created_at ON user_verifications(created_at DESC);

-- Verification History Table (for tracking verification changes)
CREATE TABLE IF NOT EXISTS verification_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id UUID NOT NULL REFERENCES user_verifications(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status VARCHAR(50) NOT NULL,
  reviewed_by UUID REFERENCES auth.users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_verification_history_verification_id ON verification_history(verification_id);
CREATE INDEX IF NOT EXISTS idx_verification_history_user_id ON verification_history(user_id);

-- System Maintenance Table (for system alerts)
CREATE TABLE IF NOT EXISTS system_maintenance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_maintenance_scheduled_start ON system_maintenance(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_system_maintenance_is_active ON system_maintenance(is_active);

-- System Announcements Table (for important updates)
CREATE TABLE IF NOT EXISTS system_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  is_active BOOLEAN DEFAULT TRUE,
  action_url VARCHAR(500),
  target_audience VARCHAR(50) DEFAULT 'all' CHECK (target_audience IN ('all', 'verified_users', 'unverified_users', 'organizers', 'admins')),
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_system_announcements_is_active ON system_announcements(is_active);
CREATE INDEX IF NOT EXISTS idx_system_announcements_priority ON system_announcements(priority);
CREATE INDEX IF NOT EXISTS idx_system_announcements_created_at ON system_announcements(created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE user_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_maintenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_announcements ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_verifications
CREATE POLICY "Users can view their own verifications"
  ON user_verifications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own verifications"
  ON user_verifications FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own pending verifications"
  ON user_verifications FOR UPDATE
  USING (auth.uid() = user_id AND status = 'pending');

CREATE POLICY "Admins can view all verifications"
  ON user_verifications FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM auth.users 
      WHERE auth.users.id = auth.uid() 
      AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
    )
  );

CREATE POLICY "Admins can update all verifications"
  ON user_verifications FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM auth.users 
      WHERE auth.users.id = auth.uid() 
      AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
    )
  );

-- RLS Policies for verification_history
CREATE POLICY "Users can view their own verification history"
  ON verification_history FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all verification history"
  ON verification_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM auth.users 
      WHERE auth.users.id = auth.uid() 
      AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
    )
  );

CREATE POLICY "System can insert verification history"
  ON verification_history FOR INSERT
  WITH CHECK (true);

-- RLS Policies for system_maintenance
CREATE POLICY "Everyone can view active maintenance"
  ON system_maintenance FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Admins can manage maintenance"
  ON system_maintenance FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM auth.users 
      WHERE auth.users.id = auth.uid() 
      AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
    )
  );

-- RLS Policies for system_announcements
CREATE POLICY "Everyone can view active announcements"
  ON system_announcements FOR SELECT
  USING (is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW()));

CREATE POLICY "Admins can manage announcements"
  ON system_announcements FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM auth.users 
      WHERE auth.users.id = auth.uid() 
      AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
    )
  );

-- Function to update updated_at timestamp
CREATE TRIGGER update_user_verifications_updated_at
  BEFORE UPDATE ON user_verifications
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Function to create verification history entry when status changes
CREATE OR REPLACE FUNCTION create_verification_history()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO verification_history (verification_id, user_id, status, reviewed_by, notes)
    VALUES (NEW.id, NEW.user_id, NEW.status, NEW.reviewed_by, NEW.admin_notes);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to create verification history
CREATE TRIGGER create_verification_history_trigger
  AFTER UPDATE OF status ON user_verifications
  FOR EACH ROW
  EXECUTE FUNCTION create_verification_history();

-- Function to check if user is verified (for use in other queries)
CREATE OR REPLACE FUNCTION is_user_verified(user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_verifications
    WHERE user_id = user_uuid
    AND status = 'approved'
    AND (expires_at IS NULL OR expires_at > NOW())
  );
END;
$$ LANGUAGE plpgsql;




-- ==========================================
-- START OF supabase_notifications_setup.sql
-- ==========================================

-- Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL, -- 'timely_suggestion', 'price_alert', 'last_chance', 'nearby_alert', 'system_alert'
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  priority VARCHAR(20) DEFAULT 'medium', -- 'low', 'medium', 'high', 'urgent'
  read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  action_url VARCHAR(500),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(user_id, read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_priority ON notifications(priority);

-- User Notification Preferences Table
CREATE TABLE IF NOT EXISTS user_notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  frequency VARCHAR(20) DEFAULT 'real-time', -- 'real-time', 'daily-digest', 'weekly-digest'
  categories JSONB DEFAULT '{
    "music": true,
    "sports": true,
    "food": true,
    "tech": true,
    "arts": true,
    "business": true,
    "education": true,
    "other": true
  }',
  quiet_hours JSONB DEFAULT '{
    "enabled": true,
    "start": "22:00",
    "end": "08:00"
  }',
  priority_level VARCHAR(20) DEFAULT 'all', -- 'all', 'urgent-only', 'high-priority'
  location_based BOOLEAN DEFAULT TRUE,
  max_daily_notifications INTEGER DEFAULT 3,
  timely_suggestions BOOLEAN DEFAULT TRUE,
  price_alerts BOOLEAN DEFAULT TRUE,
  last_chance_reminders BOOLEAN DEFAULT TRUE,
  nearby_alerts BOOLEAN DEFAULT TRUE,
  weather_alerts BOOLEAN DEFAULT TRUE,
  traffic_reminders BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_id ON user_notification_preferences(user_id);

-- Event Views Table (for tracking which events users view for price alerts)
CREATE TABLE IF NOT EXISTS event_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_event_views_user_id ON event_views(user_id);
CREATE INDEX IF NOT EXISTS idx_event_views_event_id ON event_views(event_id);
CREATE INDEX IF NOT EXISTS idx_event_views_viewed_at ON event_views(viewed_at DESC);

-- User Locations Table (for location-based notifications)
CREATE TABLE IF NOT EXISTS user_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  city VARCHAR(100),
  state VARCHAR(100),
  country VARCHAR(100),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_locations_user_id ON user_locations(user_id);

-- Price History Table (for tracking price changes)
CREATE TABLE IF NOT EXISTS event_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  price DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(10) DEFAULT 'USD',
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_price_history_event_id ON event_price_history(event_id);
CREATE INDEX IF NOT EXISTS idx_price_history_recorded_at ON event_price_history(recorded_at DESC);

-- Row Level Security (RLS) Policies for notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own notifications"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications"
  ON notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- RLS for notification preferences
ALTER TABLE user_notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own notification preferences"
  ON user_notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notification preferences"
  ON user_notification_preferences FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own notification preferences"
  ON user_notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- RLS for event views
ALTER TABLE event_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own event views"
  ON event_views FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own event views"
  ON event_views FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- RLS for user locations
ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own location"
  ON user_locations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own location"
  ON user_locations FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own location"
  ON user_locations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_notifications_updated_at
  BEFORE UPDATE ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notification_preferences_updated_at
  BEFORE UPDATE ON user_notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_locations_updated_at
  BEFORE UPDATE ON user_locations
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();




-- ==========================================
-- START OF supabase_push_subscriptions_setup.sql
-- ==========================================

-- Push Subscriptions Table
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  keys JSONB NOT NULL, -- { p256dh: string, auth: string }
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, endpoint)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint ON push_subscriptions(endpoint);

-- Enable Row Level Security (RLS)
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own push subscriptions"
  ON push_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own push subscriptions"
  ON push_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own push subscriptions"
  ON push_subscriptions FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own push subscriptions"
  ON push_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE TRIGGER update_push_subscriptions_updated_at
  BEFORE UPDATE ON push_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();




-- ==========================================
-- START OF supabase_storage_setup.sql
-- ==========================================

-- Create storage bucket for event images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'event-images',
  'event-images',
  true,
  5242880, -- 5MB limit
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
);

-- Create storage policies for event images
CREATE POLICY "Users can upload their own event images" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'event-images' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can view event images" ON storage.objects
FOR SELECT USING (bucket_id = 'event-images');

CREATE POLICY "Users can update their own event images" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'event-images' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can delete their own event images" ON storage.objects
FOR DELETE USING (
  bucket_id = 'event-images' AND
  auth.uid()::text = (storage.foldername(name))[1]
);



-- ==========================================
-- START OF supabase_verification_storage_setup.sql
-- ==========================================

-- Create storage bucket for verification documents
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'verification-documents',
  'verification-documents',
  false, -- Private bucket for security
  10485760, -- 10MB limit
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for verification documents
-- Users can upload their own verification documents
CREATE POLICY "Users can upload their own verification documents" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'verification-documents' AND
  (storage.foldername(name))[1] = 'verifications' AND
  (storage.foldername(name))[2] = auth.uid()::text
);

-- Users can view their own verification documents
CREATE POLICY "Users can view their own verification documents" ON storage.objects
FOR SELECT USING (
  bucket_id = 'verification-documents' AND
  (storage.foldername(name))[1] = 'verifications' AND
  (storage.foldername(name))[2] = auth.uid()::text
);

-- Admins can view all verification documents
CREATE POLICY "Admins can view all verification documents" ON storage.objects
FOR SELECT USING (
  bucket_id = 'verification-documents' AND
  EXISTS (
    SELECT 1 FROM auth.users 
    WHERE auth.users.id = auth.uid() 
    AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
  )
);

-- Users can delete their own pending/rejected verification documents
CREATE POLICY "Users can delete their own verification documents" ON storage.objects
FOR DELETE USING (
  bucket_id = 'verification-documents' AND
  (storage.foldername(name))[1] = 'verifications' AND
  (storage.foldername(name))[2] = auth.uid()::text
);

-- Admins can delete any verification documents
CREATE POLICY "Admins can delete any verification documents" ON storage.objects
FOR DELETE USING (
  bucket_id = 'verification-documents' AND
  EXISTS (
    SELECT 1 FROM auth.users 
    WHERE auth.users.id = auth.uid() 
    AND (auth.users.raw_user_meta_data->>'role' = 'Administrator' OR auth.users.raw_user_meta_data->>'role' = 'Admin')
  )
);




-- ==========================================
-- START OF add_analytics_fields.sql
-- ==========================================

-- Add registration source and feedback fields to participants table
-- This enables functional analytics features

-- Add registration_source column
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS registration_source VARCHAR(50) DEFAULT 'website';

-- Add rating column for event satisfaction
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS rating INTEGER CHECK (rating >= 1 AND rating <= 5);

-- Add comments field for feedback
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS comments TEXT;

-- Add age field for demographics (optional but useful)
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS age INTEGER CHECK (age >= 1 AND age <= 150);

-- Add created_at if not exists (for analytics)
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Update existing participants to have created_at
UPDATE participants 
SET created_at = registration_date 
WHERE created_at IS NULL;

-- Add index for registration_source for faster analytics queries
CREATE INDEX IF NOT EXISTS idx_participants_registration_source ON participants(registration_source);

-- Add index for rating for faster analytics queries  
CREATE INDEX IF NOT EXISTS idx_participants_rating ON participants(rating);

-- Add index for age for faster analytics queries
CREATE INDEX IF NOT EXISTS idx_participants_age ON participants(age);

-- Update RLS policies if needed (existing policies should still work)
-- No changes needed to RLS since we're just adding optional columns

COMMENT ON COLUMN participants.registration_source IS 'Source of registration: website, social-media, email, referral, direct, other';
COMMENT ON COLUMN participants.rating IS 'Event rating from 1-5 stars';
COMMENT ON COLUMN participants.comments IS 'Feedback comments from participant';
COMMENT ON COLUMN participants.age IS 'Participant age for demographics analysis';




-- ==========================================
-- START OF add_checked_in_at_column.sql
-- ==========================================

-- Add checked_in_at column to participants table for tracking check-in timestamps
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMP WITH TIME ZONE;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_participants_checked_in_at ON participants(checked_in_at);

-- Add comment to column
COMMENT ON COLUMN participants.checked_in_at IS 'Timestamp when the participant was checked in to the event';




-- ==========================================
-- START OF add_end_time_column.sql
-- ==========================================

-- Add end_time column to events table
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS end_time VARCHAR(50);

-- Add a comment to explain the column
COMMENT ON COLUMN events.end_time IS 'Event end time in 24-hour format (HH:MM)';




-- ==========================================
-- START OF add_event_type_column.sql
-- ==========================================

-- Add event_type column to events table
-- This column indicates whether an event is 'free' or 'paid'

ALTER TABLE events 
ADD COLUMN IF NOT EXISTS event_type VARCHAR(20) DEFAULT 'free' CHECK (event_type IN ('free', 'paid'));

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);

-- Update existing events: if they have tickets, mark as 'paid', otherwise 'free'
UPDATE events 
SET event_type = CASE 
  WHEN EXISTS (
    SELECT 1 FROM tickets 
    WHERE tickets.event_id = events.id 
    AND tickets.is_active = true
  ) THEN 'paid'
  ELSE 'free'
END
WHERE event_type IS NULL OR event_type = 'free';




-- ==========================================
-- START OF add_logout_time_column.sql
-- ==========================================

-- Add logout_time column to participants table for tracking logout timestamps
ALTER TABLE participants 
ADD COLUMN IF NOT EXISTS logout_time TIMESTAMP WITH TIME ZONE;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_participants_logout_time ON participants(logout_time);

-- Add comment to column
COMMENT ON COLUMN participants.logout_time IS 'Timestamp when the participant logged out from the event';




-- ==========================================
-- START OF update_events_visibility.sql
-- ==========================================

-- Update RLS policies to allow all users to view all events
-- This makes events public and visible to everyone

-- Drop ALL existing policies first to avoid conflicts
DROP POLICY IF EXISTS "Users can view their own events" ON events;
DROP POLICY IF EXISTS "All users can view all events" ON events;
DROP POLICY IF EXISTS "Anonymous users can view events" ON events;

-- Create a new policy that allows all authenticated users to view all events
CREATE POLICY "All users can view all events" ON events
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Keep the existing policies for insert, update, and delete (only owners can modify)
-- These policies remain unchanged:
-- - Users can insert their own events
-- - Users can update their own events  
-- - Users can delete their own events

-- Optional: Add a policy to allow anonymous users to view events (if you want public access)
-- Uncomment the following lines if you want events to be visible without login:
-- CREATE POLICY "Anonymous users can view events" ON events
--   FOR SELECT USING (true);



-- ==========================================
-- START OF database/admin_user_management.sql
-- ==========================================

-- Admin User Management Functions
-- Run these in Supabase SQL Editor to enable user management operations

-- Drop existing functions if they exist (in case return types changed)
DROP FUNCTION IF EXISTS update_user_role(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS update_user_status(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS delete_user(UUID) CASCADE;

-- Function to update user role
CREATE OR REPLACE FUNCTION update_user_role(user_id UUID, new_role TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSON;
BEGIN
  -- Update user metadata role
  UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{role}',
    to_jsonb(new_role)
  ),
  updated_at = NOW()
  WHERE id = user_id;

  -- Check if update was successful
  IF FOUND THEN
    SELECT json_build_object(
      'success', true,
      'message', 'User role updated successfully',
      'user_id', user_id,
      'new_role', new_role
    ) INTO result;
  ELSE
    SELECT json_build_object(
      'success', false,
      'message', 'User not found',
      'user_id', user_id
    ) INTO result;
  END IF;

  RETURN result;
END;
$$;

-- Function to update user status (active/inactive)
CREATE OR REPLACE FUNCTION update_user_status(user_id UUID, status TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSON;
  banned_until_value TIMESTAMPTZ;
BEGIN
  -- If status is 'suspended', ban user for 1 year
  -- If status is 'inactive', ban user indefinitely
  -- If status is 'active', remove ban
  CASE status
    WHEN 'suspended' THEN
      banned_until_value := NOW() + INTERVAL '1 year';
    WHEN 'inactive' THEN
      banned_until_value := '9999-12-31'::TIMESTAMPTZ;
    WHEN 'active' THEN
      banned_until_value := NULL;
    ELSE
      banned_until_value := NULL;
  END CASE;

  -- Update user ban status
  UPDATE auth.users
  SET banned_until = banned_until_value,
      updated_at = NOW()
  WHERE id = user_id;

  -- Check if update was successful
  IF FOUND THEN
    SELECT json_build_object(
      'success', true,
      'message', 'User status updated successfully',
      'user_id', user_id,
      'status', status
    ) INTO result;
  ELSE
    SELECT json_build_object(
      'success', false,
      'message', 'User not found',
      'user_id', user_id
    ) INTO result;
  END IF;

  RETURN result;
END;
$$;

-- Function to delete user (soft delete by banning)
-- Note: Hard delete requires Supabase Admin API
CREATE OR REPLACE FUNCTION delete_user(user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSON;
BEGIN
  -- Soft delete by banning user indefinitely
  UPDATE auth.users
  SET banned_until = '9999-12-31'::TIMESTAMPTZ,
      updated_at = NOW()
  WHERE id = user_id;

  -- Check if update was successful
  IF FOUND THEN
    SELECT json_build_object(
      'success', true,
      'message', 'User deleted successfully (soft delete)',
      'user_id', user_id
    ) INTO result;
  ELSE
    SELECT json_build_object(
      'success', false,
      'message', 'User not found',
      'user_id', user_id
    ) INTO result;
  END IF;

  RETURN result;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION update_user_role(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_user_status(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_user(UUID) TO authenticated;

-- Test functions
-- SELECT update_user_role('user-uuid-here', 'admin');
-- SELECT update_user_status('user-uuid-here', 'suspended');
-- SELECT delete_user('user-uuid-here');





-- ==========================================
-- START OF database/get_all_users.sql
-- ==========================================

-- Function to get all users from auth.users for admin management
-- Run this in Supabase SQL Editor to create the function

-- Drop existing function if it exists (in case return type changed)
DROP FUNCTION IF EXISTS get_all_users() CASCADE;

CREATE OR REPLACE FUNCTION get_all_users()
RETURNS TABLE (
  id UUID,
  email TEXT,
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  role TEXT,
  organization TEXT,
  created_at TIMESTAMPTZ,
  last_sign_in_at TIMESTAMPTZ,
  email_confirmed_at TIMESTAMPTZ,
  is_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id,
    u.email::TEXT,
    COALESCE((u.raw_user_meta_data->>'first_name')::TEXT, '') as first_name,
    COALESCE((u.raw_user_meta_data->>'last_name')::TEXT, '') as last_name,
    COALESCE((u.raw_user_meta_data->>'phone')::TEXT, '') as phone,
    COALESCE((u.raw_user_meta_data->>'role')::TEXT, 'organizer') as role,
    COALESCE((u.raw_user_meta_data->>'organization')::TEXT, '') as organization,
    u.created_at,
    u.last_sign_in_at,
    u.email_confirmed_at,
    CASE 
      WHEN u.banned_until IS NOT NULL AND u.banned_until > NOW() THEN FALSE
      ELSE TRUE
    END as is_active
  FROM auth.users u
  ORDER BY u.created_at DESC;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_all_users() TO authenticated;

-- Test the function
-- SELECT * FROM get_all_users();





-- ==========================================
-- START OF database/get_user_count.sql
-- ==========================================

-- Function to get total user count from auth.users
-- Run this in Supabase SQL Editor to create the function

CREATE OR REPLACE FUNCTION get_user_count()
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::bigint FROM auth.users;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_user_count() TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_count() TO anon;

-- Test the function
-- SELECT get_user_count();



-- ==========================================
-- START OF supabase_status_triggers.sql
-- ==========================================

-- Create a function to automatically update event status based on dates
CREATE OR REPLACE FUNCTION update_event_status()
RETURNS TRIGGER AS $$
DECLARE
    event_start TIMESTAMP;
    event_end TIMESTAMP;
    current_time TIMESTAMP := NOW();
    new_status TEXT;
BEGIN
    -- Parse event date and time (handle time zone properly)
    IF NEW.time IS NOT NULL THEN
        -- Convert time to timestamp by combining with date
        event_start := (NEW.date::DATE || ' ' || NEW.time::TIME)::TIMESTAMP;
    ELSE
        -- Default to start of day if no time specified
        event_start := NEW.date::DATE::TIMESTAMP;
    END IF;
    
    -- Default to 2 hours duration if no end time specified
    event_end := event_start + INTERVAL '2 hours';
    
    -- Determine status based on current time
    IF NEW.status = 'cancelled' THEN
        new_status := 'cancelled';
    ELSIF current_time < event_start THEN
        new_status := 'upcoming';
    ELSIF current_time >= event_start AND current_time <= event_end THEN
        new_status := 'ongoing';
    ELSE
        new_status := 'completed';
    END IF;
    
    -- Update the status if it has changed
    IF NEW.status != new_status THEN
        NEW.status := new_status;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update status on insert/update
DROP TRIGGER IF EXISTS trigger_update_event_status ON events;
CREATE TRIGGER trigger_update_event_status
    BEFORE INSERT OR UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_event_status();

-- Create a function to update all event statuses (for manual calls)
CREATE OR REPLACE FUNCTION update_all_event_statuses()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    event_record RECORD;
    event_start TIMESTAMP;
    event_end TIMESTAMP;
    current_time TIMESTAMP := NOW();
    new_status TEXT;
BEGIN
    -- Loop through all events
    FOR event_record IN 
        SELECT id, date, time, status 
        FROM events 
        WHERE status != 'cancelled'
    LOOP
        -- Parse event date and time (handle time zone properly)
        IF event_record.time IS NOT NULL THEN
            -- Convert time to timestamp by combining with date
            event_start := (event_record.date::DATE || ' ' || event_record.time::TIME)::TIMESTAMP;
        ELSE
            -- Default to start of day if no time specified
            event_start := event_record.date::DATE::TIMESTAMP;
        END IF;
        event_end := event_start + INTERVAL '2 hours';
        
        -- Determine new status
        IF current_time < event_start THEN
            new_status := 'upcoming';
        ELSIF current_time >= event_start AND current_time <= event_end THEN
            new_status := 'ongoing';
        ELSE
            new_status := 'completed';
        END IF;
        
        -- Update if status has changed
        IF event_record.status != new_status THEN
            UPDATE events 
            SET status = new_status 
            WHERE id = event_record.id;
            updated_count := updated_count + 1;
        END IF;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Create a scheduled job to run status updates every hour (optional)
-- Note: This requires pg_cron extension to be enabled
-- SELECT cron.schedule('update-event-statuses', '0 * * * *', 'SELECT update_all_event_statuses();');



-- ==========================================
-- START OF supabase_status_triggers_simple.sql
-- ==========================================

-- Temporarily disable the trigger to avoid conflicts during event creation
DROP TRIGGER IF EXISTS trigger_update_event_status ON events;

-- Create a simpler function that only updates status when explicitly called
CREATE OR REPLACE FUNCTION update_event_status_manual(event_id UUID, new_status TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE events 
    SET status = new_status 
    WHERE id = event_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Create a function to update all event statuses based on current time
CREATE OR REPLACE FUNCTION update_all_event_statuses()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    event_record RECORD;
    event_start TIMESTAMP WITH TIME ZONE;
    event_end TIMESTAMP WITH TIME ZONE;
    current_time TIMESTAMP WITH TIME ZONE := NOW();
    new_status TEXT;
BEGIN
    -- Loop through all events
    FOR event_record IN 
        SELECT id, date, time, status 
        FROM events 
        WHERE status != 'cancelled'
    LOOP
        -- Parse event date and time (handle time zone properly)
        IF event_record.time IS NOT NULL THEN
            -- Convert time to timestamp by combining with date
            event_start := (event_record.date::DATE || ' ' || event_record.time::TEXT)::TIMESTAMP WITH TIME ZONE;
        ELSE
            -- Default to start of day if no time specified
            event_start := event_record.date::DATE::TIMESTAMP WITH TIME ZONE;
        END IF;
        event_end := event_start + INTERVAL '2 hours';
        
        -- Determine new status
        IF current_time < event_start THEN
            new_status := 'upcoming';
        ELSIF current_time >= event_start AND current_time <= event_end THEN
            new_status := 'ongoing';
        ELSE
            new_status := 'completed';
        END IF;
        
        -- Update if status has changed
        IF event_record.status != new_status THEN
            UPDATE events 
            SET status = new_status 
            WHERE id = event_record.id;
            updated_count := updated_count + 1;
        END IF;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;



-- ==========================================
-- START OF supabase_status_triggers_fixed.sql
-- ==========================================

-- Create a function to automatically update event status based on dates
CREATE OR REPLACE FUNCTION update_event_status()
RETURNS TRIGGER AS $$
DECLARE
    event_start TIMESTAMP WITH TIME ZONE;
    event_end TIMESTAMP WITH TIME ZONE;
    current_time TIMESTAMP WITH TIME ZONE := NOW();
    new_status TEXT;
BEGIN
    -- Parse event date and time (handle time zone properly)
    IF NEW.time IS NOT NULL THEN
        -- Convert time to timestamp by combining with date
        event_start := (NEW.date::DATE || ' ' || NEW.time::TEXT)::TIMESTAMP WITH TIME ZONE;
    ELSE
        -- Default to start of day if no time specified
        event_start := NEW.date::DATE::TIMESTAMP WITH TIME ZONE;
    END IF;
    
    -- Default to 2 hours duration if no end time specified
    event_end := event_start + INTERVAL '2 hours';
    
    -- Determine status based on current time
    IF NEW.status = 'cancelled' THEN
        new_status := 'cancelled';
    ELSIF current_time < event_start THEN
        new_status := 'upcoming';
    ELSIF current_time >= event_start AND current_time <= event_end THEN
        new_status := 'ongoing';
    ELSE
        new_status := 'completed';
    END IF;
    
    -- Update the status if it has changed
    IF NEW.status != new_status THEN
        NEW.status := new_status;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update status on insert/update
DROP TRIGGER IF EXISTS trigger_update_event_status ON events;
CREATE TRIGGER trigger_update_event_status
    BEFORE INSERT OR UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION update_event_status();

-- Create a function to update all event statuses (for manual calls)
CREATE OR REPLACE FUNCTION update_all_event_statuses()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    event_record RECORD;
    event_start TIMESTAMP WITH TIME ZONE;
    event_end TIMESTAMP WITH TIME ZONE;
    current_time TIMESTAMP WITH TIME ZONE := NOW();
    new_status TEXT;
BEGIN
    -- Loop through all events
    FOR event_record IN 
        SELECT id, date, time, status 
        FROM events 
        WHERE status != 'cancelled'
    LOOP
        -- Parse event date and time (handle time zone properly)
        IF event_record.time IS NOT NULL THEN
            -- Convert time to timestamp by combining with date
            event_start := (event_record.date::DATE || ' ' || event_record.time::TEXT)::TIMESTAMP WITH TIME ZONE;
        ELSE
            -- Default to start of day if no time specified
            event_start := event_record.date::DATE::TIMESTAMP WITH TIME ZONE;
        END IF;
        event_end := event_start + INTERVAL '2 hours';
        
        -- Determine new status
        IF current_time < event_start THEN
            new_status := 'upcoming';
        ELSIF current_time >= event_start AND current_time <= event_end THEN
            new_status := 'ongoing';
        ELSE
            new_status := 'completed';
        END IF;
        
        -- Update if status has changed
        IF event_record.status != new_status THEN
            UPDATE events 
            SET status = new_status 
            WHERE id = event_record.id;
            updated_count := updated_count + 1;
        END IF;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Create a scheduled job to run status updates every hour (optional)
-- Note: This requires pg_cron extension to be enabled
-- SELECT cron.schedule('update-event-statuses', '0 * * * *', 'SELECT update_all_event_statuses();');



-- ==========================================
-- START OF fix_participants_rls.sql
-- ==========================================

-- Fix RLS policies for participants table to allow event registration
-- This script updates the participants table policies to properly allow registration

-- Drop ALL existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can register for events" ON participants;
DROP POLICY IF EXISTS "Users can view participants of their events" ON participants;
DROP POLICY IF EXISTS "Users can update their own registrations" ON participants;
DROP POLICY IF EXISTS "Users can delete their own registrations" ON participants;
DROP POLICY IF EXISTS "Users can view participants" ON participants;
DROP POLICY IF EXISTS "Event creators can manage participants" ON participants;

-- Create updated policies for participants table
-- Allow users to register for any event (insert their own registration)
CREATE POLICY "Users can register for events" ON participants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow users to view participants of events they created OR their own registrations
CREATE POLICY "Users can view participants" ON participants
  FOR SELECT USING (
    auth.uid() = user_id OR 
    EXISTS (
      SELECT 1 FROM events 
      WHERE events.id = participants.event_id 
      AND events.user_id = auth.uid()
    )
  );

-- Allow users to update their own registrations
CREATE POLICY "Users can update their own registrations" ON participants
  FOR UPDATE USING (auth.uid() = user_id);

-- Allow users to delete their own registrations
CREATE POLICY "Users can delete their own registrations" ON participants
  FOR DELETE USING (auth.uid() = user_id);

-- Optional: Allow event creators to manage all participants of their events
-- Uncomment the following if you want event creators to be able to update/delete any participant
-- CREATE POLICY "Event creators can manage participants" ON participants
--   FOR ALL USING (
--     EXISTS (
--       SELECT 1 FROM events 
--       WHERE events.id = participants.event_id 
--       AND events.user_id = auth.uid()
--     )
--   );



-- ==========================================
-- START OF fix_participants_viewing_rls.sql
-- ==========================================

-- Update RLS policies for participants table to allow broader access
-- This script allows event organizers to view all participants

-- Drop existing policies
DROP POLICY IF EXISTS "Users can register for events" ON participants;
DROP POLICY IF EXISTS "Users can view participants of their events" ON participants;
DROP POLICY IF EXISTS "Users can update their own registrations" ON participants;
DROP POLICY IF EXISTS "Users can delete their own registrations" ON participants;
DROP POLICY IF EXISTS "Users can view participants" ON participants;
DROP POLICY IF EXISTS "Event creators can manage participants" ON participants;

-- Create updated policies for participants table
-- Allow users to register for any event (insert their own registration)
CREATE POLICY "Users can register for events" ON participants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Allow ALL authenticated users to view participants (for admin/organizer purposes)
-- This allows the Participants page to show all participants from all events
CREATE POLICY "All authenticated users can view participants" ON participants
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Allow users to update their own registrations
CREATE POLICY "Users can update their own registrations" ON participants
  FOR UPDATE USING (auth.uid() = user_id);

-- Allow users to delete their own registrations
CREATE POLICY "Users can delete their own registrations" ON participants
  FOR DELETE USING (auth.uid() = user_id);

-- Optional: Allow event creators to manage all participants of their events
-- Uncomment the following if you want event creators to be able to update/delete any participant
-- CREATE POLICY "Event creators can manage participants" ON participants
--   FOR ALL USING (
--     EXISTS (
--       SELECT 1 FROM events 
--       WHERE events.id = participants.event_id 
--       AND events.user_id = auth.uid()
--     )
--   );



-- ==========================================
-- START OF fix_verification_rls.sql
-- ==========================================

-- Fix RLS policies for user_verifications table
-- The issue: Regular users can't query auth.users directly
-- Solution: Use a security definer function to check admin status

-- Create a function to check if current user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users 
    WHERE auth.users.id = auth.uid() 
    AND (
      auth.users.raw_user_meta_data->>'role' = 'Administrator' 
      OR auth.users.raw_user_meta_data->>'role' = 'Admin'
    )
  );
END;
$$;

-- Drop existing admin policies
DROP POLICY IF EXISTS "Admins can view all verifications" ON user_verifications;
DROP POLICY IF EXISTS "Admins can update all verifications" ON user_verifications;
DROP POLICY IF EXISTS "Admins can view all verification history" ON verification_history;
DROP POLICY IF EXISTS "Admins can manage maintenance" ON system_maintenance;
DROP POLICY IF EXISTS "Admins can manage announcements" ON system_announcements;

-- Recreate admin policies using the function
CREATE POLICY "Admins can view all verifications"
  ON user_verifications FOR SELECT
  USING (is_admin());

CREATE POLICY "Admins can update all verifications"
  ON user_verifications FOR UPDATE
  USING (is_admin());

CREATE POLICY "Admins can view all verification history"
  ON verification_history FOR SELECT
  USING (is_admin());

CREATE POLICY "Admins can manage maintenance"
  ON system_maintenance FOR ALL
  USING (is_admin());

CREATE POLICY "Admins can manage announcements"
  ON system_announcements FOR ALL
  USING (is_admin());

-- Also fix the storage policies that reference auth.users
-- Drop existing storage policies
DROP POLICY IF EXISTS "Admins can view all verification documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete any verification documents" ON storage.objects;

-- Recreate storage policies using the function
CREATE POLICY "Admins can view all verification documents" ON storage.objects
FOR SELECT USING (
  bucket_id = 'verification-documents' AND
  is_admin()
);

CREATE POLICY "Admins can delete any verification documents" ON storage.objects
FOR DELETE USING (
  bucket_id = 'verification-documents' AND
  is_admin()
);



