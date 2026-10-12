package ca.kestrelsports.app;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import androidx.browser.customtabs.CustomTabsIntent;

/** Opens the existing Kestrel website in the user's trusted browser session.
 * This preserves Google OAuth, which may be blocked in embedded WebViews. */
public class MainActivity extends Activity {
    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri site = Uri.parse("https://kestrelsports.ca/");
        try {
            CustomTabsIntent tabs = new CustomTabsIntent.Builder().setShowTitle(true).build();
            tabs.launchUrl(this, site);
        } catch (Exception ignored) {
            startActivity(new Intent(Intent.ACTION_VIEW, site));
        }
        finish();
    }
}
