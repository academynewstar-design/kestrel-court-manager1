import { createClient } from '@supabase/supabase-js';
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://ngfsceffxkhvbhtmtygg.supabase.co';
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_XIEsbHo3Tt5hnDumZk1Y-A_s_KFpPrs';
export const supabase = createClient(supabaseUrl, supabasePublishableKey);