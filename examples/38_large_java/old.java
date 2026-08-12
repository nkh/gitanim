package com.example.notifications;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Legacy NotificationService implementation. Uses synchronized blocks to
 * coordinate work and performs I/O sequentially on the calling thread.
 *
 * Threading model: each call to sendNotification blocks the caller until all
 * channels have been attempted. Failed sends are retried inline, with no
 * backoff or circuit breaker.
 */
public class NotificationService {

    private final Map<String, Channel> channels = new HashMap<>();
    private final Map<String, User> users = new ConcurrentHashMap<>();
    private final Map<String, List<NotificationRecord>> history = new ConcurrentHashMap<>();
    private final AtomicLong idGenerator = new AtomicLong(1);
    private final Object lock = new Object();

    public void registerChannel(Channel channel) {
        synchronized (lock) {
            channels.put(channel.getName(), channel);
        }
    }

    public void removeChannel(String name) {
        synchronized (lock) {
            channels.remove(name);
        }
    }

    public void registerUser(User user) {
        users.put(user.getId(), user);
    }

    public User getUser(String userId) {
        return users.get(userId);
    }

    /**
     * Send a notification to all of the user's preferred channels. Returns
     * a result map keyed by channel name to "ok"/"fail" strings.
     */
    public Map<String, String> sendNotification(String userId, Notification notification) {
        User user = users.get(userId);
        if (user == null) {
            throw new IllegalArgumentException("Unknown user: " + userId);
        }
        Map<String, String> results = new HashMap<>();
        List<Channel> targets;
        synchronized (lock) {
            targets = new ArrayList<>();
            for (String preferred : user.getPreferredChannels()) {
                Channel c = channels.get(preferred);
                if (c != null) {
                    targets.add(c);
                }
            }
        }
        if (targets.isEmpty()) {
            throw new IllegalStateException("No channels available for user: " + userId);
        }
        for (Channel channel : targets) {
            boolean ok = false;
            for (int attempt = 1; attempt <= 3; attempt++) {
                try {
                    channel.send(user, notification);
                    ok = true;
                    break;
                } catch (Exception e) {
                    // Last attempt failed — record and continue.
                    if (attempt == 3) {
                        System.err.println("Send failed on channel " + channel.getName()
                            + " for user " + userId + ": " + e.getMessage());
                    }
                }
            }
            results.put(channel.getName(), ok ? "ok" : "fail");
            recordDelivery(userId, notification, channel.getName(), ok);
        }
        return results;
    }

    public Map<String, String> broadcast(Notification notification, List<String> userIds) {
        Map<String, String> summary = new HashMap<>();
        int success = 0;
        int failure = 0;
        for (String userId : userIds) {
            try {
                Map<String, String> perUser = sendNotification(userId, notification);
                boolean anyOk = false;
                for (String v : perUser.values()) {
                    if ("ok".equals(v)) {
                        anyOk = true;
                        break;
                    }
                }
                if (anyOk) {
                    success++;
                } else {
                    failure++;
                }
            } catch (Exception e) {
                failure++;
                System.err.println("Broadcast failed for user " + userId + ": " + e.getMessage());
            }
        }
        summary.put("success", String.valueOf(success));
        summary.put("failure", String.valueOf(failure));
        return summary;
    }

    private void recordDelivery(String userId, Notification notification,
                                String channelName, boolean success) {
        NotificationRecord record = new NotificationRecord(
            idGenerator.getAndIncrement(),
            userId,
            notification.getId(),
            channelName,
            success,
            System.currentTimeMillis()
        );
        history.computeIfAbsent(userId, k -> new ArrayList<>()).add(record);
    }

    public List<NotificationRecord> getHistory(String userId) {
        List<NotificationRecord> records = history.get(userId);
        if (records == null) {
            return new ArrayList<>();
        }
        synchronized (lock) {
            return new ArrayList<>(records);
        }
    }

    public Map<String, Object> getStats() {
        synchronized (lock) {
            Map<String, Object> stats = new HashMap<>();
            stats.put("users", users.size());
            stats.put("channels", channels.size());
            int totalDeliveries = 0;
            int successfulDeliveries = 0;
            for (List<NotificationRecord> records : history.values()) {
                totalDeliveries += records.size();
                for (NotificationRecord r : records) {
                    if (r.isSuccess()) {
                        successfulDeliveries++;
                    }
                }
            }
            stats.put("total_deliveries", totalDeliveries);
            stats.put("successful_deliveries", successfulDeliveries);
            stats.put("success_rate",
                totalDeliveries == 0 ? 0.0
                    : (double) successfulDeliveries / totalDeliveries);
            return stats;
        }
    }

    public void shutdown() {
        synchronized (lock) {
            for (Channel c : channels.values()) {
                try {
                    c.close();
                } catch (Exception e) {
                    System.err.println("Error closing channel " + c.getName() + ": " + e.getMessage());
                }
            }
            channels.clear();
            history.clear();
        }
    }

    /**
     * Apply a simple template substitution to a notification body. Templates
     * use ${var} placeholders that are replaced with values from the
     * notification's metadata map.
     */
    public String applyTemplate(Notification notification) {
        synchronized (lock) {
            String body = notification.getBody();
            Map<String, String> vars = notification.getMetadata();
            if (vars == null) {
                return body;
            }
            StringBuilder out = new StringBuilder();
            int i = 0;
            while (i < body.length()) {
                char c = body.charAt(i);
                if (c == '$' && i + 1 < body.length() && body.charAt(i + 1) == '{') {
                    int end = body.indexOf('}', i + 2);
                    if (end == -1) {
                        out.append(c);
                        i++;
                        continue;
                    }
                    String key = body.substring(i + 2, end);
                    String value = vars.get(key);
                    if (value != null) {
                        out.append(value);
                    } else {
                        out.append("${").append(key).append("}");
                    }
                    i = end + 1;
                } else {
                    out.append(c);
                    i++;
                }
            }
            return out.toString();
        }
    }

    /**
     * Schedule a notification to be sent at a future time. This naive
     * implementation simply sleeps the calling thread. Real implementations
     * would use a ScheduledExecutorService.
     */
    public Map<String, String> scheduleNotification(String userId, Notification notification,
                                                    long delayMillis) {
        try {
            Thread.sleep(delayMillis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            Map<String, String> cancelled = new HashMap<>();
            cancelled.put("status", "cancelled");
            return cancelled;
        }
        return sendNotification(userId, notification);
    }

    /**
     * Cancel the most recent notification for a user, if it hasn't been
     * delivered yet. Since this implementation delivers synchronously,
     * cancellation only works for scheduled notifications still in flight.
     */
    public boolean cancelNotification(String userId, String notificationId) {
        synchronized (lock) {
            List<NotificationRecord> records = history.get(userId);
            if (records == null) {
                return false;
            }
            for (int i = records.size() - 1; i >= 0; i--) {
                NotificationRecord r = records.get(i);
                if (r.getNotificationId().equals(notificationId)) {
                    // In the legacy implementation we can't really cancel.
                    // Just pretend we did.
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Return all delivery records for a user that match the given channel
     * name. Returns an empty list if no records match.
     */
    public List<NotificationRecord> getHistoryByChannel(String userId, String channelName) {
        List<NotificationRecord> all = getHistory(userId);
        List<NotificationRecord> filtered = new ArrayList<>();
        synchronized (lock) {
            for (NotificationRecord r : all) {
                if (r.getChannel().equals(channelName)) {
                    filtered.add(r);
                }
            }
        }
        return filtered;
    }

    /**
     * Return all delivery records for a user that were successful. Used by
     * downstream reporting tools to build engagement metrics.
     */
    public List<NotificationRecord> getSuccessfulDeliveries(String userId) {
        List<NotificationRecord> all = getHistory(userId);
        List<NotificationRecord> filtered = new ArrayList<>();
        synchronized (lock) {
            for (NotificationRecord r : all) {
                if (r.isSuccess()) {
                    filtered.add(r);
                }
            }
        }
        return filtered;
    }

    /**
     * Compute a delivery success rate per channel across all users. Returns
     * a map keyed by channel name to a percentage (0.0 to 1.0).
     */
    public Map<String, Double> successRateByChannel() {
        synchronized (lock) {
            Map<String, int[]> counts = new HashMap<>();
            for (List<NotificationRecord> records : history.values()) {
                for (NotificationRecord r : records) {
                    int[] pair = counts.computeIfAbsent(r.getChannel(), k -> new int[2]);
                    pair[0]++; // total
                    if (r.isSuccess()) {
                        pair[1]++; // successes
                    }
                }
            }
            Map<String, Double> rates = new HashMap<>();
            for (Map.Entry<String, int[]> e : counts.entrySet()) {
                int[] pair = e.getValue();
                rates.put(e.getKey(), pair[0] == 0 ? 0.0 : (double) pair[1] / pair[0]);
            }
            return rates;
        }
    }

    // ------------------------------------------------------------------
    // Domain types
    // ------------------------------------------------------------------

    public interface Channel {
        String getName();
        void send(User user, Notification notification) throws Exception;
        void close() throws Exception;
    }

    public static class User {
        private final String id;
        private final String name;
        private final String email;
        private final String phone;
        private final String deviceToken;
        private final List<String> preferredChannels;

        public User(String id, String name, String email, String phone,
                    String deviceToken, List<String> preferredChannels) {
            this.id = id;
            this.name = name;
            this.email = email;
            this.phone = phone;
            this.deviceToken = deviceToken;
            this.preferredChannels = preferredChannels;
        }

        public String getId() { return id; }
        public String getName() { return name; }
        public String getEmail() { return email; }
        public String getPhone() { return phone; }
        public String getDeviceToken() { return deviceToken; }
        public List<String> getPreferredChannels() {
            return preferredChannels;
        }
    }

    public static class Notification {
        private final String id;
        private final String type;
        private final String subject;
        private final String body;
        private final Map<String, String> metadata;

        public Notification(String id, String type, String subject, String body,
                            Map<String, String> metadata) {
            this.id = id;
            this.type = type;
            this.subject = subject;
            this.body = body;
            this.metadata = metadata;
        }

        public String getId() { return id; }
        public String getType() { return type; }
        public String getSubject() { return subject; }
        public String getBody() { return body; }
        public Map<String, String> getMetadata() { return metadata; }
    }

    public static class NotificationRecord {
        private final long id;
        private final String userId;
        private final String notificationId;
        private final String channel;
        private final boolean success;
        private final long timestamp;

        public NotificationRecord(long id, String userId, String notificationId,
                                  String channel, boolean success, long timestamp) {
            this.id = id;
            this.userId = userId;
            this.notificationId = notificationId;
            this.channel = channel;
            this.success = success;
            this.timestamp = timestamp;
        }

        public long getId() { return id; }
        public String getUserId() { return userId; }
        public String getNotificationId() { return notificationId; }
        public String getChannel() { return channel; }
        public boolean isSuccess() { return success; }
        public long getTimestamp() { return timestamp; }
    }

    // ------------------------------------------------------------------
    // Sample channel implementations
    // ------------------------------------------------------------------

    public static class EmailChannel implements Channel {
        private final String smtpHost;
        private final int smtpPort;
        private final String fromAddress;

        public EmailChannel(String smtpHost, int smtpPort, String fromAddress) {
            this.smtpHost = smtpHost;
            this.smtpPort = smtpPort;
            this.fromAddress = fromAddress;
        }

        @Override
        public String getName() { return "email"; }

        @Override
        public void send(User user, Notification notification) throws Exception {
            if (user.getEmail() == null) {
                throw new IllegalArgumentException("User has no email address");
            }
            // Simulate SMTP send. In real code this would open a socket.
            System.out.println("EMAIL to=" + user.getEmail()
                + " from=" + fromAddress
                + " subject=" + notification.getSubject()
                + " body=" + notification.getBody().substring(0, Math.min(50, notification.getBody().length())));
        }

        @Override
        public void close() throws Exception {
            System.out.println("Closing SMTP connection to " + smtpHost + ":" + smtpPort);
        }
    }

    public static class SmsChannel implements Channel {
        private final String apiEndpoint;
        private final String apiKey;

        public SmsChannel(String apiEndpoint, String apiKey) {
            this.apiEndpoint = apiEndpoint;
            this.apiKey = apiKey;
        }

        @Override
        public String getName() { return "sms"; }

        @Override
        public void send(User user, Notification notification) throws Exception {
            if (user.getPhone() == null) {
                throw new IllegalArgumentException("User has no phone number");
            }
            System.out.println("SMS to=" + user.getPhone()
                + " body=" + notification.getBody().substring(0, Math.min(140, notification.getBody().length())));
        }

        @Override
        public void close() throws Exception {
            System.out.println("Closing SMS API connection to " + apiEndpoint);
        }
    }

    public static class PushChannel implements Channel {
        private final String fcmServerKey;

        public PushChannel(String fcmServerKey) {
            this.fcmServerKey = fcmServerKey;
        }

        @Override
        public String getName() { return "push"; }

        @Override
        public void send(User user, Notification notification) throws Exception {
            if (user.getDeviceToken() == null) {
                throw new IllegalArgumentException("User has no device token");
            }
            System.out.println("PUSH to=" + user.getDeviceToken()
                + " title=" + notification.getSubject()
                + " body=" + notification.getBody().substring(0, Math.min(80, notification.getBody().length())));
        }

        @Override
        public void close() throws Exception {
            System.out.println("Closing FCM connection");
        }
    }

    // ------------------------------------------------------------------
    // Main entry point for ad-hoc testing
    // ------------------------------------------------------------------

    public static void main(String[] args) {
        NotificationService service = new NotificationService();
        service.registerChannel(new EmailChannel("smtp.example.com", 587, "noreply@example.com"));
        service.registerChannel(new SmsChannel("https://sms.example.com/api", "secret"));
        service.registerChannel(new PushChannel("fcm-server-key"));

        User alice = new User("u1", "Alice", "alice@example.com", "+15551234567",
            "device-token-alice", List.of("email", "push"));
        service.registerUser(alice);

        Notification n = new Notification("n1", "welcome", "Welcome!",
            "Thanks for signing up. We're glad to have you.", Map.of("source", "web"));
        Map<String, String> results = service.sendNotification("u1", n);
        System.out.println("Results: " + results);

        System.out.println("Stats: " + service.getStats());
        service.shutdown();
    }
}
