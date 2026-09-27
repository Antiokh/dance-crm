-- AUTO-GENERATED. DO NOT EDIT.
-- Source: live Supabase table DDL versioning
-- Schema:   public
-- Entity:   tables
-- Mode:     table_bundle
-- Updated:  2026-09-27T07:42:04.594Z

-- table: bookings

CREATE TABLE public.bookings (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  slot_id uuid NOT NULL,
  dancer_id uuid NOT NULL,
  status booking_status NOT NULL DEFAULT 'booked'::booking_status,
  attendance_status attendance_status,
  dance_role_id smallint,
  is_trial boolean NOT NULL DEFAULT false,
  booked_at timestamp with time zone NOT NULL DEFAULT now(),
  cancelled_at timestamp with time zone,
  cancellation_type booking_cancellation_type,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT bookings_check CHECK (status <> 'cancelled'::booking_status OR cancelled_at IS NOT NULL),
  CONSTRAINT bookings_check1 CHECK (status = 'cancelled'::booking_status OR cancellation_type IS NULL),
  CONSTRAINT bookings_dance_role_id_fkey FOREIGN KEY (dance_role_id) REFERENCES l_dance_role(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT bookings_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT bookings_pkey PRIMARY KEY (id),
  CONSTRAINT bookings_slot_id_dancer_id_key UNIQUE (slot_id, dancer_id),
  CONSTRAINT bookings_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES class_slots(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX bookings_slot_status_idx ON public.bookings USING btree (slot_id, status, booked_at);
CREATE INDEX bookings_dancer_booked_idx ON public.bookings USING btree (dancer_id, booked_at DESC);
CREATE INDEX bookings_dance_role_idx ON public.bookings USING btree (slot_id, dance_role_id, status);
CREATE INDEX bookings_dance_role_id_idx ON public.bookings USING btree (dance_role_id);
CREATE TRIGGER bookings_refresh_class_slot_role_counts AFTER INSERT OR DELETE OR UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.refresh_class_slot_role_counts();
CREATE TRIGGER bookings_touch_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
CREATE POLICY bookings_select ON public.bookings FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.can_operate_slot(slot_id)));

-- table: class_schedule_instructors

CREATE TABLE public.class_schedule_instructors (
  schedule_id uuid NOT NULL,
  trainer_id uuid NOT NULL,
  trainer_role group_trainer_role NOT NULL DEFAULT 'lead'::group_trainer_role,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT class_schedule_instructors_pkey PRIMARY KEY (schedule_id, trainer_id),
  CONSTRAINT class_schedule_instructors_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES class_schedules(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT class_schedule_instructors_trainer_id_fkey FOREIGN KEY (trainer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX class_schedule_instructors_trainer_idx ON public.class_schedule_instructors USING btree (trainer_id, schedule_id);
CREATE TRIGGER class_schedule_instructors_require_trainer BEFORE INSERT OR UPDATE OF trainer_id ON public.class_schedule_instructors FOR EACH ROW EXECUTE FUNCTION private.ensure_class_instructor_role();
ALTER TABLE public.class_schedule_instructors ENABLE ROW LEVEL SECURITY;
CREATE POLICY class_schedule_instructors_admin_delete ON public.class_schedule_instructors FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedule_instructors_admin_insert ON public.class_schedule_instructors FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedule_instructors_admin_update ON public.class_schedule_instructors FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedule_instructors_select ON public.class_schedule_instructors FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM class_schedules cs
  WHERE ((cs.id = class_schedule_instructors.schedule_id) AND private.can_view_class(cs.group_id, cs.visibility)))));

-- table: class_schedules

CREATE TABLE public.class_schedules (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  group_id uuid NOT NULL,
  venue_id uuid,
  weekday smallint NOT NULL,
  start_time time without time zone NOT NULL,
  end_time time without time zone NOT NULL,
  timezone text NOT NULL DEFAULT 'Europe/Belgrade'::text,
  valid_from date NOT NULL DEFAULT CURRENT_DATE,
  valid_until date,
  capacity_override integer,
  active boolean NOT NULL DEFAULT true,
  visibility class_visibility NOT NULL DEFAULT 'public'::class_visibility,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT class_schedules_capacity_override_check CHECK (capacity_override IS NULL OR capacity_override > 0),
  CONSTRAINT class_schedules_check CHECK (end_time > start_time),
  CONSTRAINT class_schedules_check1 CHECK (valid_until IS NULL OR valid_until >= valid_from),
  CONSTRAINT class_schedules_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT class_schedules_pkey PRIMARY KEY (id),
  CONSTRAINT class_schedules_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES venues(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT class_schedules_weekday_check CHECK (weekday >= 0 AND weekday <= 6)
);
CREATE INDEX class_schedules_group_active_idx ON public.class_schedules USING btree (group_id, active, valid_from, valid_until);
CREATE INDEX class_schedules_venue_idx ON public.class_schedules USING btree (venue_id);
CREATE TRIGGER class_schedules_touch_updated_at BEFORE UPDATE ON public.class_schedules FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER class_schedules_validate BEFORE INSERT OR UPDATE ON public.class_schedules FOR EACH ROW EXECUTE FUNCTION private.validate_class_schedule();
ALTER TABLE public.class_schedules ENABLE ROW LEVEL SECURITY;
CREATE POLICY class_schedules_admin_delete ON public.class_schedules FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedules_admin_insert ON public.class_schedules FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedules_admin_update ON public.class_schedules FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_schedules_select ON public.class_schedules FOR SELECT TO authenticated USING (private.can_view_class(group_id, visibility));

-- table: class_slot_instructors

CREATE TABLE public.class_slot_instructors (
  slot_id uuid NOT NULL,
  trainer_id uuid NOT NULL,
  trainer_role group_trainer_role NOT NULL DEFAULT 'lead'::group_trainer_role,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT class_slot_instructors_pkey PRIMARY KEY (slot_id, trainer_id),
  CONSTRAINT class_slot_instructors_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES class_slots(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT class_slot_instructors_trainer_id_fkey FOREIGN KEY (trainer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX class_slot_instructors_trainer_idx ON public.class_slot_instructors USING btree (trainer_id, slot_id);
CREATE TRIGGER class_slot_instructors_require_trainer BEFORE INSERT OR UPDATE OF trainer_id ON public.class_slot_instructors FOR EACH ROW EXECUTE FUNCTION private.ensure_class_instructor_role();
ALTER TABLE public.class_slot_instructors ENABLE ROW LEVEL SECURITY;
CREATE POLICY class_slot_instructors_admin_delete ON public.class_slot_instructors FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slot_instructors_admin_insert ON public.class_slot_instructors FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slot_instructors_admin_update ON public.class_slot_instructors FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slot_instructors_select ON public.class_slot_instructors FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM class_slots cs
  WHERE ((cs.id = class_slot_instructors.slot_id) AND (private.can_view_class(cs.group_id, cs.visibility) OR private.has_booking_for_slot(cs.id))))));

-- table: class_slots

CREATE TABLE public.class_slots (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  group_id uuid NOT NULL,
  schedule_id uuid,
  occurrence_date date,
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone NOT NULL,
  venue_id uuid,
  capacity_override integer,
  visibility class_visibility NOT NULL DEFAULT 'public'::class_visibility,
  status class_slot_status NOT NULL DEFAULT 'scheduled'::class_slot_status,
  source class_slot_source NOT NULL DEFAULT 'manual'::class_slot_source,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  leader_booked_count integer NOT NULL DEFAULT 0,
  follower_booked_count integer NOT NULL DEFAULT 0,
  CONSTRAINT class_slots_capacity_override_check CHECK (capacity_override IS NULL OR capacity_override > 0),
  CONSTRAINT class_slots_check CHECK (ends_at > starts_at),
  CONSTRAINT class_slots_check1 CHECK (source <> 'schedule'::class_slot_source OR schedule_id IS NOT NULL AND occurrence_date IS NOT NULL),
  CONSTRAINT class_slots_check2 CHECK (status <> 'cancelled'::class_slot_status OR cancelled_at IS NOT NULL),
  CONSTRAINT class_slots_follower_booked_count_nonnegative CHECK (follower_booked_count >= 0),
  CONSTRAINT class_slots_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT class_slots_leader_booked_count_nonnegative CHECK (leader_booked_count >= 0),
  CONSTRAINT class_slots_pkey PRIMARY KEY (id),
  CONSTRAINT class_slots_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES class_schedules(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT class_slots_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES venues(id) ON UPDATE CASCADE ON DELETE SET NULL
);
CREATE UNIQUE INDEX class_slots_schedule_occurrence_unique ON public.class_slots USING btree (schedule_id, occurrence_date) WHERE ((schedule_id IS NOT NULL) AND (occurrence_date IS NOT NULL));
CREATE INDEX class_slots_group_starts_idx ON public.class_slots USING btree (group_id, starts_at, status);
CREATE INDEX class_slots_starts_status_idx ON public.class_slots USING btree (starts_at, status);
CREATE INDEX class_slots_schedule_idx ON public.class_slots USING btree (schedule_id, starts_at);
CREATE INDEX class_slots_venue_idx ON public.class_slots USING btree (venue_id);
CREATE TRIGGER class_slots_cancel_bookings AFTER UPDATE OF status ON public.class_slots FOR EACH ROW EXECUTE FUNCTION private.cancel_bookings_for_cancelled_slot();
CREATE TRIGGER class_slots_touch_updated_at BEFORE UPDATE ON public.class_slots FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.class_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY class_slots_admin_delete ON public.class_slots FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slots_admin_insert ON public.class_slots FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slots_admin_update ON public.class_slots FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY class_slots_select ON public.class_slots FOR SELECT TO authenticated USING ((private.can_view_class(group_id, visibility) OR private.has_booking_for_slot(id)));

-- table: dance_events

CREATE TABLE public.dance_events (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  event_type dance_event_type NOT NULL,
  title text NOT NULL,
  description text,
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone,
  venue_id uuid,
  style_id smallint,
  published boolean NOT NULL DEFAULT false,
  cancelled_at timestamp with time zone,
  created_by uuid DEFAULT private.current_dancer_id(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT dance_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES dancer(id) ON DELETE SET NULL,
  CONSTRAINT dance_events_pkey PRIMARY KEY (id),
  CONSTRAINT dance_events_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id) ON DELETE SET NULL,
  CONSTRAINT dance_events_time_order CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT dance_events_title_check CHECK (length(btrim(title)) > 0),
  CONSTRAINT dance_events_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL
);
CREATE INDEX dance_events_upcoming_idx ON public.dance_events USING btree (starts_at) WHERE (published AND (cancelled_at IS NULL));
CREATE INDEX dance_events_venue_idx ON public.dance_events USING btree (venue_id);
CREATE INDEX dance_events_style_idx ON public.dance_events USING btree (style_id);
CREATE TRIGGER dance_events_touch_updated_at BEFORE UPDATE ON public.dance_events FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.dance_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY dance_events_admin_delete ON public.dance_events FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_events_admin_insert ON public.dance_events FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_events_admin_update ON public.dance_events FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_events_select ON public.dance_events FOR SELECT TO authenticated USING (((published AND (cancelled_at IS NULL)) OR private.has_app_role('administrator'::app_role)));

-- table: dance_group

CREATE TABLE public.dance_group (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  style_id smallint NOT NULL,
  title text NOT NULL,
  description text,
  max_capacity integer,
  approval_required boolean NOT NULL DEFAULT false,
  enrollment_status group_enrollment_status NOT NULL DEFAULT 'open'::group_enrollment_status,
  starts_on date,
  ends_on date,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  level_id bigint,
  CONSTRAINT dance_group_check CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
  CONSTRAINT dance_group_level_style_fkey FOREIGN KEY (level_id, style_id) REFERENCES styles_levels(id, style_id) ON DELETE RESTRICT,
  CONSTRAINT dance_group_max_capacity_check CHECK (max_capacity IS NULL OR max_capacity > 0),
  CONSTRAINT dance_group_pkey PRIMARY KEY (id),
  CONSTRAINT dance_group_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id),
  CONSTRAINT dance_group_title_check CHECK (length(btrim(title)) >= 1 AND length(btrim(title)) <= 160)
);
CREATE INDEX dance_group_style_active_idx ON public.dance_group USING btree (style_id, active, enrollment_status);
CREATE TRIGGER dance_group_generate_title BEFORE INSERT OR UPDATE ON public.dance_group FOR EACH ROW EXECUTE FUNCTION private.set_generated_group_title();
CREATE TRIGGER dance_group_touch_updated_at BEFORE UPDATE ON public.dance_group FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.dance_group ENABLE ROW LEVEL SECURITY;
CREATE POLICY dance_group_admin_delete ON public.dance_group FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_group_admin_insert ON public.dance_group FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_group_admin_update ON public.dance_group FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY dance_group_public_select ON public.dance_group FOR SELECT TO anon USING (active);
CREATE POLICY dance_group_select ON public.dance_group FOR SELECT TO authenticated USING (private.can_view_group(id));

-- table: dancer

CREATE TABLE public.dancer (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  telegram_id bigint,
  first_name text,
  last_name text,
  telegram_username text,
  custom_name text,
  tg_user_json jsonb,
  lang_code text NOT NULL DEFAULT 'en'::text,
  premium boolean NOT NULL DEFAULT false,
  tg_web_app jsonb,
  primary_role smallint,
  saved boolean NOT NULL DEFAULT false,
  auth_user_id uuid NOT NULL,
  CONSTRAINT dancer_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT dancer_auth_user_id_key UNIQUE (auth_user_id),
  CONSTRAINT dancer_pkey PRIMARY KEY (id),
  CONSTRAINT dancer_primary_role_fkey FOREIGN KEY (primary_role) REFERENCES l_dance_role(id),
  CONSTRAINT dancer_telegram_id_key UNIQUE (telegram_id)
);
CREATE INDEX dancer_primary_role_idx ON public.dancer USING btree (primary_role);
CREATE TRIGGER dancer_refresh_group_titles AFTER UPDATE OF custom_name, first_name, last_name, telegram_username ON public.dancer FOR EACH ROW EXECUTE FUNCTION private.refresh_group_titles_from_dancer();
ALTER TABLE public.dancer ENABLE ROW LEVEL SECURITY;
CREATE POLICY dancer_public_trainers_select ON public.dancer FOR SELECT TO anon USING ((EXISTS ( SELECT 1
   FROM (group_trainers gt
     JOIN dance_group g ON ((g.id = gt.group_id)))
  WHERE ((gt.trainer_id = dancer.id) AND g.active AND ((gt.starts_on IS NULL) OR (gt.starts_on <= CURRENT_DATE)) AND ((gt.ends_on IS NULL) OR (gt.ends_on >= CURRENT_DATE))))));
CREATE POLICY dancer_select_directory ON public.dancer FOR SELECT TO authenticated USING (true);
CREATE POLICY dancer_update_self ON public.dancer FOR UPDATE TO authenticated USING ((auth_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((auth_user_id = ( SELECT auth.uid() AS uid)));

-- table: dancer_app_roles

CREATE TABLE public.dancer_app_roles (
  dancer_id uuid NOT NULL,
  role app_role NOT NULL,
  granted_at timestamp with time zone NOT NULL DEFAULT now(),
  granted_by uuid,
  CONSTRAINT dancer_app_roles_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT dancer_app_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT dancer_app_roles_pkey PRIMARY KEY (dancer_id, role)
);
CREATE INDEX dancer_app_roles_role_idx ON public.dancer_app_roles USING btree (role, dancer_id);
CREATE INDEX dancer_app_roles_granted_by_idx ON public.dancer_app_roles USING btree (granted_by);
ALTER TABLE public.dancer_app_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY dancer_app_roles_select ON public.dancer_app_roles FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role)));

-- table: dancer_style_profile

CREATE TABLE public.dancer_style_profile (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  dancer_id uuid NOT NULL,
  style_id smallint NOT NULL,
  is_leader boolean NOT NULL,
  is_trainer boolean NOT NULL DEFAULT false,
  is_default boolean NOT NULL DEFAULT false,
  level_id bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT dancer_style_profile_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON DELETE CASCADE,
  CONSTRAINT dancer_style_profile_dancer_id_style_id_is_leader_key UNIQUE (dancer_id, style_id, is_leader),
  CONSTRAINT dancer_style_profile_level_id_style_id_fkey FOREIGN KEY (level_id, style_id) REFERENCES styles_levels(id, style_id) ON DELETE SET NULL,
  CONSTRAINT dancer_style_profile_pkey PRIMARY KEY (id),
  CONSTRAINT dancer_style_profile_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX dancer_style_profile_one_default ON public.dancer_style_profile USING btree (dancer_id, style_id) WHERE is_default;
CREATE INDEX dancer_style_profile_dancer_style_idx ON public.dancer_style_profile USING btree (dancer_id, style_id);
CREATE TRIGGER dancer_style_profile_touch_updated_at BEFORE UPDATE ON public.dancer_style_profile FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.dancer_style_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY dancer_style_profile_delete_own ON public.dancer_style_profile FOR DELETE TO authenticated USING ((dancer_id = private.current_dancer_id()));
CREATE POLICY dancer_style_profile_insert_own ON public.dancer_style_profile FOR INSERT TO authenticated WITH CHECK ((dancer_id = private.current_dancer_id()));
CREATE POLICY dancer_style_profile_select_own ON public.dancer_style_profile FOR SELECT TO authenticated USING ((dancer_id = private.current_dancer_id()));
CREATE POLICY dancer_style_profile_update_own ON public.dancer_style_profile FOR UPDATE TO authenticated USING ((dancer_id = private.current_dancer_id())) WITH CHECK ((dancer_id = private.current_dancer_id()));

-- table: debug_events

CREATE TABLE public.debug_events (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  source text NOT NULL,
  message text NOT NULL,
  payload jsonb,
  CONSTRAINT debug_events_pkey PRIMARY KEY (id)
);
CREATE INDEX debug_events_created_at_idx ON public.debug_events USING btree (created_at DESC);
CREATE INDEX debug_events_source_idx ON public.debug_events USING btree (source);
ALTER TABLE public.debug_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY debug_events_service_only ON public.debug_events TO service_role USING (true) WITH CHECK (true);

-- table: event_attendance

CREATE TABLE public.event_attendance (
  event_id uuid NOT NULL,
  dancer_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  cancelled_at timestamp with time zone,
  CONSTRAINT event_attendance_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON DELETE CASCADE,
  CONSTRAINT event_attendance_event_id_fkey FOREIGN KEY (event_id) REFERENCES dance_events(id) ON DELETE CASCADE,
  CONSTRAINT event_attendance_pkey PRIMARY KEY (event_id, dancer_id)
);
CREATE INDEX event_attendance_dancer_idx ON public.event_attendance USING btree (dancer_id, event_id);
CREATE INDEX event_attendance_active_idx ON public.event_attendance USING btree (event_id, dancer_id) WHERE (cancelled_at IS NULL);
CREATE TRIGGER event_attendance_touch_updated_at BEFORE UPDATE ON public.event_attendance FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.event_attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY event_attendance_insert_self ON public.event_attendance FOR INSERT TO authenticated WITH CHECK ((dancer_id = private.current_dancer_id()));
CREATE POLICY event_attendance_select ON public.event_attendance FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role)));
CREATE POLICY event_attendance_update_self ON public.event_attendance FOR UPDATE TO authenticated USING ((dancer_id = private.current_dancer_id())) WITH CHECK ((dancer_id = private.current_dancer_id()));

-- table: group_memberships

CREATE TABLE public.group_memberships (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  group_id uuid NOT NULL,
  dancer_id uuid NOT NULL,
  status group_membership_status NOT NULL DEFAULT 'pending'::group_membership_status,
  requested_at timestamp with time zone NOT NULL DEFAULT now(),
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  approved_at timestamp with time zone,
  approved_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT group_memberships_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT group_memberships_check CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at),
  CONSTRAINT group_memberships_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT group_memberships_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT group_memberships_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX group_memberships_current_unique ON public.group_memberships USING btree (group_id, dancer_id) WHERE (status = ANY (ARRAY['pending'::group_membership_status, 'active'::group_membership_status]));
CREATE INDEX group_memberships_dancer_idx ON public.group_memberships USING btree (dancer_id, status, group_id);
CREATE INDEX group_memberships_group_idx ON public.group_memberships USING btree (group_id, status, dancer_id);
CREATE INDEX group_memberships_approved_by_idx ON public.group_memberships USING btree (approved_by);
CREATE TRIGGER group_memberships_normalize_request BEFORE INSERT ON public.group_memberships FOR EACH ROW EXECUTE FUNCTION private.normalize_group_membership_request();
CREATE TRIGGER group_memberships_touch_updated_at BEFORE UPDATE ON public.group_memberships FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.group_memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY group_memberships_insert_self ON public.group_memberships FOR INSERT TO authenticated WITH CHECK ((dancer_id = private.current_dancer_id()));
CREATE POLICY group_memberships_manage_update ON public.group_memberships FOR UPDATE TO authenticated USING (private.can_manage_group(group_id)) WITH CHECK (private.can_manage_group(group_id));
CREATE POLICY group_memberships_select ON public.group_memberships FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.can_manage_group(group_id)));

-- table: group_trainers

CREATE TABLE public.group_trainers (
  group_id uuid NOT NULL,
  trainer_id uuid NOT NULL,
  trainer_role group_trainer_role NOT NULL DEFAULT 'lead'::group_trainer_role,
  starts_on date,
  ends_on date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT group_trainers_check CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
  CONSTRAINT group_trainers_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT group_trainers_pkey PRIMARY KEY (group_id, trainer_id),
  CONSTRAINT group_trainers_trainer_id_fkey FOREIGN KEY (trainer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX group_trainers_trainer_idx ON public.group_trainers USING btree (trainer_id, group_id);
CREATE TRIGGER group_trainers_refresh_group_title AFTER INSERT OR DELETE OR UPDATE ON public.group_trainers FOR EACH ROW EXECUTE FUNCTION private.refresh_group_title_from_trainers();
CREATE TRIGGER group_trainers_require_trainer_role BEFORE INSERT OR UPDATE OF trainer_id ON public.group_trainers FOR EACH ROW EXECUTE FUNCTION private.ensure_group_trainer_role();
ALTER TABLE public.group_trainers ENABLE ROW LEVEL SECURITY;
CREATE POLICY group_trainers_admin_delete ON public.group_trainers FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY group_trainers_admin_insert ON public.group_trainers FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY group_trainers_admin_update ON public.group_trainers FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY group_trainers_public_select ON public.group_trainers FOR SELECT TO anon USING ((EXISTS ( SELECT 1
   FROM dance_group g
  WHERE ((g.id = group_trainers.group_id) AND g.active))));
CREATE POLICY group_trainers_select ON public.group_trainers FOR SELECT TO authenticated USING (private.can_view_group(group_id));

-- table: home_attention_items

CREATE TABLE public.home_attention_items (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  title text NOT NULL,
  body text,
  event_id uuid,
  group_id uuid,
  dancer_id uuid,
  priority smallint NOT NULL DEFAULT 0,
  published boolean NOT NULL DEFAULT false,
  starts_at timestamp with time zone NOT NULL DEFAULT now(),
  ends_at timestamp with time zone,
  created_by uuid DEFAULT private.current_dancer_id(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT home_attention_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES dancer(id) ON DELETE SET NULL,
  CONSTRAINT home_attention_items_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON DELETE CASCADE,
  CONSTRAINT home_attention_items_event_id_fkey FOREIGN KEY (event_id) REFERENCES dance_events(id) ON DELETE CASCADE,
  CONSTRAINT home_attention_items_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON DELETE CASCADE,
  CONSTRAINT home_attention_items_pkey PRIMARY KEY (id),
  CONSTRAINT home_attention_items_title_check CHECK (length(btrim(title)) > 0),
  CONSTRAINT home_attention_single_target CHECK (group_id IS NULL OR dancer_id IS NULL),
  CONSTRAINT home_attention_time_order CHECK (ends_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX home_attention_active_idx ON public.home_attention_items USING btree (published, starts_at, ends_at, priority DESC);
CREATE INDEX home_attention_group_idx ON public.home_attention_items USING btree (group_id) WHERE (group_id IS NOT NULL);
CREATE INDEX home_attention_dancer_idx ON public.home_attention_items USING btree (dancer_id) WHERE (dancer_id IS NOT NULL);
CREATE TRIGGER home_attention_touch_updated_at BEFORE UPDATE ON public.home_attention_items FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.home_attention_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY home_attention_admin_delete ON public.home_attention_items FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY home_attention_admin_insert ON public.home_attention_items FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY home_attention_admin_update ON public.home_attention_items FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY home_attention_select ON public.home_attention_items FOR SELECT TO authenticated USING ((private.has_app_role('administrator'::app_role) OR (published AND (starts_at <= now()) AND ((ends_at IS NULL) OR (ends_at > now())) AND (((group_id IS NULL) AND (dancer_id IS NULL)) OR (dancer_id = private.current_dancer_id()) OR (EXISTS ( SELECT 1
   FROM group_memberships gm
  WHERE ((gm.group_id = home_attention_items.group_id) AND (gm.dancer_id = private.current_dancer_id()) AND (gm.status = 'active'::group_membership_status) AND ((gm.starts_at IS NULL) OR (gm.starts_at <= now())) AND ((gm.ends_at IS NULL) OR (gm.ends_at > now())))))) AND ((event_id IS NULL) OR (EXISTS ( SELECT 1
   FROM dance_events e
  WHERE ((e.id = home_attention_items.event_id) AND e.published AND (e.cancelled_at IS NULL))))))));

-- table: l_dance_role

CREATE TABLE public.l_dance_role (
  id smallint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  title_en text,
  title_ru text,
  title_sr text,
  CONSTRAINT l_dance_role_pkey PRIMARY KEY (id)
);
ALTER TABLE public.l_dance_role ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable read access for all users" ON public.l_dance_role FOR SELECT TO PUBLIC USING (true);

-- table: l_dance_style

CREATE TABLE public.l_dance_style (
  id smallint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  title_en text,
  title_ru text,
  title_sr text,
  is_partner_dance boolean NOT NULL DEFAULT true,
  CONSTRAINT l_dance_style_pkey PRIMARY KEY (id)
);
CREATE TRIGGER dance_style_refresh_group_titles AFTER UPDATE OF title_en, title_ru, title_sr ON public.l_dance_style FOR EACH ROW EXECUTE FUNCTION private.refresh_group_titles_from_style();
ALTER TABLE public.l_dance_style ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable read access for all users" ON public.l_dance_style FOR SELECT TO PUBLIC USING (true);

-- table: overbook_requests

CREATE TABLE public.overbook_requests (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  booking_id uuid NOT NULL,
  slot_id uuid NOT NULL,
  dancer_id uuid NOT NULL,
  status overbook_request_status NOT NULL DEFAULT 'pending'::overbook_request_status,
  requested_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  review_note text,
  notification_queued_at timestamp with time zone,
  notification_sent_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT overbook_requests_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE,
  CONSTRAINT overbook_requests_booking_id_key UNIQUE (booking_id),
  CONSTRAINT overbook_requests_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON DELETE CASCADE,
  CONSTRAINT overbook_requests_pkey PRIMARY KEY (id),
  CONSTRAINT overbook_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES dancer(id) ON DELETE SET NULL,
  CONSTRAINT overbook_requests_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES class_slots(id) ON DELETE CASCADE,
  CONSTRAINT overbook_review_shape CHECK (status = 'pending'::overbook_request_status AND reviewed_at IS NULL AND reviewed_by IS NULL OR status <> 'pending'::overbook_request_status)
);
CREATE INDEX overbook_requests_slot_status_idx ON public.overbook_requests USING btree (slot_id, status, requested_at);
CREATE INDEX overbook_requests_dancer_idx ON public.overbook_requests USING btree (dancer_id, requested_at DESC);
CREATE TRIGGER overbook_requests_touch_updated_at BEFORE UPDATE ON public.overbook_requests FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.overbook_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY overbook_requests_select ON public.overbook_requests FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.can_operate_slot(slot_id)));

-- table: student_subscription_groups

CREATE TABLE public.student_subscription_groups (
  subscription_id uuid NOT NULL,
  group_id uuid NOT NULL,
  CONSTRAINT student_subscription_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT student_subscription_groups_pkey PRIMARY KEY (subscription_id, group_id),
  CONSTRAINT student_subscription_groups_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES student_subscriptions(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX student_subscription_groups_group_idx ON public.student_subscription_groups USING btree (group_id, subscription_id);
ALTER TABLE public.student_subscription_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_subscription_groups_select ON public.student_subscription_groups FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM student_subscriptions s
  WHERE ((s.id = student_subscription_groups.subscription_id) AND ((s.dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role))))));

-- table: student_subscriptions

CREATE TABLE public.student_subscriptions (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  dancer_id uuid NOT NULL,
  plan_id uuid,
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone,
  status student_subscription_status NOT NULL DEFAULT 'active'::student_subscription_status,
  usage_mode_snapshot subscription_usage_mode NOT NULL,
  included_classes_snapshot integer,
  allowed_skips_snapshot integer NOT NULL DEFAULT 0,
  replacement_grace_days_snapshot integer NOT NULL DEFAULT 0,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  issued_by uuid,
  cancelled_at timestamp with time zone,
  cancellation_reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT student_subscriptions_allowed_skips_snapshot_check CHECK (allowed_skips_snapshot >= 0),
  CONSTRAINT student_subscriptions_check CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT student_subscriptions_check1 CHECK (usage_mode_snapshot = 'credits'::subscription_usage_mode AND included_classes_snapshot IS NOT NULL AND included_classes_snapshot > 0 OR usage_mode_snapshot = 'unlimited'::subscription_usage_mode AND included_classes_snapshot IS NULL),
  CONSTRAINT student_subscriptions_check2 CHECK (status <> 'cancelled'::student_subscription_status OR cancelled_at IS NOT NULL),
  CONSTRAINT student_subscriptions_dancer_id_fkey FOREIGN KEY (dancer_id) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT student_subscriptions_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT student_subscriptions_pkey PRIMARY KEY (id),
  CONSTRAINT student_subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES subscription_plans(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT student_subscriptions_replacement_grace_days_snapshot_check CHECK (replacement_grace_days_snapshot >= 0)
);
CREATE INDEX student_subscriptions_dancer_idx ON public.student_subscriptions USING btree (dancer_id, starts_at, ends_at, status);
CREATE INDEX student_subscriptions_plan_idx ON public.student_subscriptions USING btree (plan_id);
CREATE INDEX student_subscriptions_issued_by_idx ON public.student_subscriptions USING btree (issued_by);
CREATE TRIGGER student_subscriptions_touch_updated_at BEFORE UPDATE ON public.student_subscriptions FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.student_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_subscriptions_select ON public.student_subscriptions FOR SELECT TO authenticated USING (((dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role)));

-- table: student_subscription_styles

CREATE TABLE public.student_subscription_styles (
  subscription_id uuid NOT NULL,
  style_id smallint NOT NULL,
  CONSTRAINT student_subscription_styles_pkey PRIMARY KEY (subscription_id, style_id),
  CONSTRAINT student_subscription_styles_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT student_subscription_styles_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES student_subscriptions(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX student_subscription_styles_style_idx ON public.student_subscription_styles USING btree (style_id, subscription_id);
ALTER TABLE public.student_subscription_styles ENABLE ROW LEVEL SECURITY;
CREATE POLICY student_subscription_styles_select ON public.student_subscription_styles FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM student_subscriptions s
  WHERE ((s.id = student_subscription_styles.subscription_id) AND ((s.dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role))))));

-- table: styles_levels

CREATE TABLE public.styles_levels (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  style_id smallint NOT NULL,
  code text NOT NULL,
  title_en text NOT NULL,
  title_ru text,
  title_sr text,
  rank_order smallint NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT styles_levels_id_style_id_key UNIQUE (id, style_id),
  CONSTRAINT styles_levels_pkey PRIMARY KEY (id),
  CONSTRAINT styles_levels_style_id_code_key UNIQUE (style_id, code),
  CONSTRAINT styles_levels_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id) ON DELETE CASCADE
);
CREATE TRIGGER styles_levels_refresh_group_titles AFTER UPDATE OF title_en, title_ru, title_sr ON public.styles_levels FOR EACH ROW EXECUTE FUNCTION private.refresh_group_titles_from_level();
ALTER TABLE public.styles_levels ENABLE ROW LEVEL SECURITY;
CREATE POLICY styles_levels_read_active ON public.styles_levels FOR SELECT TO authenticated, anon USING (active);

-- table: subscription_plan_groups

CREATE TABLE public.subscription_plan_groups (
  plan_id uuid NOT NULL,
  group_id uuid NOT NULL,
  CONSTRAINT subscription_plan_groups_group_id_fkey FOREIGN KEY (group_id) REFERENCES dance_group(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT subscription_plan_groups_pkey PRIMARY KEY (plan_id, group_id),
  CONSTRAINT subscription_plan_groups_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES subscription_plans(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX subscription_plan_groups_group_idx ON public.subscription_plan_groups USING btree (group_id, plan_id);
ALTER TABLE public.subscription_plan_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_plan_groups_select ON public.subscription_plan_groups FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM subscription_plans p
  WHERE ((p.id = subscription_plan_groups.plan_id) AND (p.active OR private.has_app_role('administrator'::app_role))))));

-- table: subscription_plans

CREATE TABLE public.subscription_plans (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  name text NOT NULL,
  description text,
  renewal_mode subscription_renewal_mode NOT NULL DEFAULT 'one_time'::subscription_renewal_mode,
  usage_mode subscription_usage_mode NOT NULL DEFAULT 'credits'::subscription_usage_mode,
  included_classes integer,
  validity_days integer,
  allowed_skips integer NOT NULL DEFAULT 0,
  replacement_grace_days integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT subscription_plans_allowed_skips_check CHECK (allowed_skips >= 0),
  CONSTRAINT subscription_plans_check CHECK (usage_mode = 'credits'::subscription_usage_mode AND included_classes IS NOT NULL AND included_classes > 0 OR usage_mode = 'unlimited'::subscription_usage_mode AND included_classes IS NULL),
  CONSTRAINT subscription_plans_name_check CHECK (length(btrim(name)) >= 1 AND length(btrim(name)) <= 160),
  CONSTRAINT subscription_plans_pkey PRIMARY KEY (id),
  CONSTRAINT subscription_plans_replacement_grace_days_check CHECK (replacement_grace_days >= 0),
  CONSTRAINT subscription_plans_validity_days_check CHECK (validity_days IS NULL OR validity_days > 0)
);
CREATE TRIGGER subscription_plans_touch_updated_at BEFORE UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_plans_select ON public.subscription_plans FOR SELECT TO authenticated USING ((active OR private.has_app_role('administrator'::app_role)));

-- table: subscription_plan_styles

CREATE TABLE public.subscription_plan_styles (
  plan_id uuid NOT NULL,
  style_id smallint NOT NULL,
  CONSTRAINT subscription_plan_styles_pkey PRIMARY KEY (plan_id, style_id),
  CONSTRAINT subscription_plan_styles_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES subscription_plans(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT subscription_plan_styles_style_id_fkey FOREIGN KEY (style_id) REFERENCES l_dance_style(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX subscription_plan_styles_style_idx ON public.subscription_plan_styles USING btree (style_id, plan_id);
ALTER TABLE public.subscription_plan_styles ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_plan_styles_select ON public.subscription_plan_styles FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM subscription_plans p
  WHERE ((p.id = subscription_plan_styles.plan_id) AND (p.active OR private.has_app_role('administrator'::app_role))))));

-- table: subscription_transactions

CREATE TABLE public.subscription_transactions (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  subscription_id uuid NOT NULL,
  booking_id uuid,
  transaction_type subscription_transaction_type NOT NULL,
  class_delta integer NOT NULL DEFAULT 0,
  skip_delta integer NOT NULL DEFAULT 0,
  reason text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT subscription_transactions_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES bookings(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT subscription_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES dancer(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT subscription_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT subscription_transactions_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES student_subscriptions(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE UNIQUE INDEX subscription_transactions_booking_type_unique ON public.subscription_transactions USING btree (subscription_id, booking_id, transaction_type) WHERE (booking_id IS NOT NULL);
CREATE INDEX subscription_transactions_subscription_idx ON public.subscription_transactions USING btree (subscription_id, created_at);
CREATE INDEX subscription_transactions_booking_idx ON public.subscription_transactions USING btree (booking_id);
CREATE INDEX subscription_transactions_created_by_idx ON public.subscription_transactions USING btree (created_by);
ALTER TABLE public.subscription_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_transactions_select ON public.subscription_transactions FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM student_subscriptions s
  WHERE ((s.id = subscription_transactions.subscription_id) AND ((s.dancer_id = private.current_dancer_id()) OR private.has_app_role('administrator'::app_role))))));

-- table: venues

CREATE TABLE public.venues (
  id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  name text NOT NULL,
  address text,
  latitude double precision,
  longitude double precision,
  capacity integer,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT venues_capacity_check CHECK (capacity IS NULL OR capacity > 0),
  CONSTRAINT venues_latitude_check CHECK (latitude IS NULL OR latitude >= '-90'::integer::double precision AND latitude <= 90::double precision),
  CONSTRAINT venues_longitude_check CHECK (longitude IS NULL OR longitude >= '-180'::integer::double precision AND longitude <= 180::double precision),
  CONSTRAINT venues_name_check CHECK (length(btrim(name)) >= 1 AND length(btrim(name)) <= 160),
  CONSTRAINT venues_pkey PRIMARY KEY (id)
);
CREATE TRIGGER venues_touch_updated_at BEFORE UPDATE ON public.venues FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;
CREATE POLICY venues_admin_delete ON public.venues FOR DELETE TO authenticated USING (private.has_app_role('administrator'::app_role));
CREATE POLICY venues_admin_insert ON public.venues FOR INSERT TO authenticated WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY venues_admin_update ON public.venues FOR UPDATE TO authenticated USING (private.has_app_role('administrator'::app_role)) WITH CHECK (private.has_app_role('administrator'::app_role));
CREATE POLICY venues_public_select ON public.venues FOR SELECT TO anon USING (active);
CREATE POLICY venues_select ON public.venues FOR SELECT TO authenticated USING ((active OR private.has_app_role('administrator'::app_role)));
