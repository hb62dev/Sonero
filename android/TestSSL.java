import java.net.URL;
import java.net.URLConnection;
import java.io.InputStream;

public class TestSSL {
    public static void main(String[] args) {
        try {
            System.setProperty("javax.net.ssl.trustStore", "C:/Users/hbriceno/Desktop/sonero/mycacerts_new");
            System.setProperty("javax.net.ssl.trustStorePassword", "changeit");
            URL url = new URL("https://dl.google.com/dl/android/maven2/com/android/application/com.android.application.gradle.plugin/8.7.0/com.android.application.gradle.plugin-8.7.0.pom");
            URLConnection conn = url.openConnection();
            InputStream is = conn.getInputStream();
            System.out.println("Connection successful! Bytes available: " + is.available());
            is.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
