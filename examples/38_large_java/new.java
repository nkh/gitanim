package com.example.notifications;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * Modern NotificationService implementation.
 *
 * Threading model: all channel I/O is performed asynchronously on a bounded
 * thread pool. Each channel send is wrapped in a CompletableFuture with retry
 * and timeout. Broadcasts fan out across the pool and aggregate via
 * CompletableFuture.allOf.
 *
 * Error handling: custom checked exceptions classify failures so callers can
 * decide whether to retry, alert, or ignore.
 */
public class NotificationService implements AutoCloseable {

    private final Map<String, Channel> channels = new ConcurrentHashMap<>();
    private final Map<String, User> users = new ConcurrentHashMap<>();
    private final Map<String, List<NotificationRecord>> history = new ConcurrentHashMap<>();
    private final AtomicLong idGenerator = new AtomicLong(1);

    private final ExecutorService executor;
    private final int sendTimeoutMillis;
    private final int maxAttempts;
    private final long retryBackoffMillis;

    public NotificationService(int poolSize, int sendTimeoutMillis,
                               int maxAttempts, long retryBackoffMillis) {
        if (poolSize <= 0) {
            throw new IllegalArgumentException("poolSize must be positive");
        }
        if (sendTimeoutMillis <= 0) {
            throw new IllegalArgumentException("sendTimeoutMillis must be positive");
        }
        if (maxAttempts <= 0) {
            throw new IllegalArgumentException("maxAttempts must be positive");
        }
        this.executor = Executors.newFixedThreadPool(poolSize, new NamedThreadFactory("notif-sender"));
        this.sendTimeoutMillis = sendTimeoutMillis;
        this.maxAttempts = maxAttempts;
        this.retryBackoffMillis = retryBackoffMillis;
    }

    public NotificationService() {
        this(Runtime.getRuntime().availableProcessors() * 2,
            5_000, 3, 200L);
    }

    // ------------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------------

    public void registerChannel(Channel channel) {
        Objects.requireNonNull(channel, "channel");
        channels.put(channel.getName(), channel);
    }

    public void removeChannel(String name) {
        channels.remove(name);
    }

    public void registerUser(User user) {
        Objects.requireNonNull(user, "user");
        users.put(user.getId(), user);
    }

    public User getUser(String userId) {
        return users.get(userId);
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    public CompletableFuture<Map<String, DeliveryResult>> sendNotificationAsync(
            String userId, Notification notification) {
        final User user = users.get(userId);
        if (user == null) {
            return CompletableFuture.failedFuture(
                new UnknownUserException(userId));
        }
        final List<Channel> targets = resolveChannels(user);
        if (targets.isEmpty()) {
            return CompletableFuture.failedFuture(
                new NoChannelsAvailableException(userId));
        }
        List<CompletableFuture<DeliveryResult>> futures = targets.stream()
            .map(c -> deliverWithRetry(user, notification, c)
                .exceptionally(ex -> new DeliveryResult(c.getName(),
                    DeliveryStatus.FAILED, ex.getMessage())))
            .collect(Collectors.toList());
        return CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
            .thenApply(v -> {
                Map<String, DeliveryResult> results = new HashMap<>();
                for (CompletableFuture<DeliveryResult> f : futures) {
                    DeliveryResult r = f.join();
                    results.put(r.getChannel(), r);
                    recordDelivery(user.getId(), notification.getId(), r);
                }
                return results;
            });
    }

    public Map<String, DeliveryResult> sendNotification(String userId,
                                                        Notification notification)
            throws NotificationException {
        try {
            return sendNotificationAsync(userId, notification)
                .get(sendTimeoutMillis * maxAttempts + 1_000L, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            throw new NotificationTimeoutException("send timed out", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new NotificationInterruptedException("interrupted", e);
        } catch (ExecutionException e) {
            Throwable cause = e.getCause();
            if (cause instanceof NotificationException) {
                throw (NotificationException) cause;
            }
            throw new NotificationException("send failed", cause);
        }
    }

    public CompletableFuture<BroadcastSummary> broadcastAsync(
            Notification notification, List<String> userIds) {
        Objects.requireNonNull(userIds, "userIds");
        List<CompletableFuture<UserBroadcastResult>> perUser = userIds.stream()
            .map(userId -> sendNotificationAsync(userId, notification)
                .handle((results, ex) -> {
                    if (ex != null) {
                        return new UserBroadcastResult(userId, 0, 0,
                            ex.getMessage());
                    }
                    int ok = 0;
                    int fail = 0;
                    for (DeliveryResult r : results.values()) {
                        if (r.getStatus() == DeliveryStatus.OK) ok++;
                        else fail++;
                    }
                    return new UserBroadcastResult(userId, ok, fail, null);
                }))
            .collect(Collectors.toList());
        return CompletableFuture.allOf(perUser.toArray(new CompletableFuture[0]))
            .thenApply(v -> {
                int totalOk = 0;
                int totalFail = 0;
                List<UserBroadcastResult> details = new ArrayList<>(perUser.size());
                for (CompletableFuture<UserBroadcastResult> f : perUser) {
                    UserBroadcastResult r = f.join();
                    details.add(r);
                    totalOk += r.successCount;
                    totalFail += r.failureCount;
                }
                return new BroadcastSummary(totalOk, totalFail, details);
            });
    }

    public List<NotificationRecord> getHistory(String userId) {
        List<NotificationRecord> records = history.get(userId);
        if (records == null) {
            return Collections.emptyList();
        }
        synchronized (records) {
            return new ArrayList<>(records);
        }
    }

    public Map<String, Object> getStats() {
        long total = 0L;
        long ok = 0L;
        for (List<NotificationRecord> records : history.values()) {
            synchronized (records) {
                total += records.size();
                for (NotificationRecord r : records) {
                    if (r.getStatus() == DeliveryStatus.OK) {
                        ok++;
                    }
                }
            }
        }
        Map<String, Object> stats = new HashMap<>();
        stats.put("users", users.size());
        stats.put("channels", channels.size());
        stats.put("total_deliveries", total);
        stats.put("successful_deliveries", ok);
        stats.put("success_rate", total == 0 ? 0.0 : (double) ok / total);
        stats.put("active_threads", ((java.util.concurrent.ThreadPoolExecutor) executor).getActiveCount());
        return stats;
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    private List<Channel> resolveChannels(User user) {
        List<Channel> targets = new ArrayList<>();
        for (String preferred : user.getPreferredChannels()) {
            Channel c = channels.get(preferred);
            if (c != null) {
                targets.add(c);
            }
        }
        return targets;
    }

    private CompletableFuture<DeliveryResult> deliverWithRetry(
            User user, Notification notification, Channel channel) {
        Supplier<DeliveryResult> attempt = () -> {
            try {
                channel.send(user, notification);
                return new DeliveryResult(channel.getName(),
                    DeliveryStatus.OK, null);
            } catch (Exception e) {
                throw new ChannelSendException(channel.getName(), e);
            }
        };
        CompletableFuture<DeliveryResult> future = CompletableFuture.supplyAsync(attempt, executor);
        for (int i = 2; i <= maxAttempts; i++) {
            final int attemptNumber = i;
            future = future.exceptionallyCompose(ex -> {
                if (ex instanceof ChannelSendException) {
                    return CompletableFuture.supplyAsync(attempt, executor)
                        .completeOnTimeout(new DeliveryResult(channel.getName(),
                            DeliveryStatus.TIMEOUT,
                            "timed out on attempt " + attemptNumber),
                            sendTimeoutMillis, TimeUnit.MILLISECONDS)
                        .thenCompose(r -> {
                            if (r.getStatus() == DeliveryStatus.OK) {
                                return CompletableFuture.completedFuture(r);
                            }
                            return CompletableFuture.failedFuture(
                                new ChannelSendException(channel.getName(),
                                    new RuntimeException(r.getMessage())));
                        });
                }
                return CompletableFuture.failedFuture(ex);
            });
        }
        return future.orTimeout(sendTimeoutMillis, TimeUnit.MILLISECONDS)
            .exceptionally(ex -> {
                Throwable cause = (ex instanceof CompletionException) ? ex.getCause() : ex;
                return new DeliveryResult(channel.getName(),
                    DeliveryStatus.FAILED, cause.getMessage());
            });
    }

    private void recordDelivery(String userId, String notificationId,
                                DeliveryResult result) {
        NotificationRecord record = new NotificationRecord(
            idGenerator.getAndIncrement(),
            userId,
            notificationId,
            result.getChannel(),
            result.getStatus(),
            System.currentTimeMillis(),
            result.getErrorMessage()
        );
        history.computeIfAbsent(userId, k -> Collections.synchronizedList(new ArrayList<>()))
               .add(record);
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    @Override
    public void close() {
        executor.shutdown();
        try {
            if (!executor.awaitTermination(5, TimeUnit.SECONDS)) {
                executor.shutdownNow();
                executor.awaitTermination(2, TimeUnit.SECONDS);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            executor.shutdownNow();
        }
        for (Channel c : channels.values()) {
            try {
                c.close();
            } catch (Exception e) {
                // Best effort; log and continue.
                System.err.println("Error closing channel " + c.getName() + ": " + e.getMessage());
            }
        }
        channels.clear();
        history.clear();
    }

    // ------------------------------------------------------------------
    // Domain types
    // ------------------------------------------------------------------

    public interface Channel {
        String getName();
        void send(User user, Notification notification) throws Exception;
        void close() throws Exception;
    }

    public enum DeliveryStatus { OK, FAILED, TIMEOUT, SKIPPED }

    public static final class User {
        private final String id;
        private final String name;
        private final String email;
        private final String phone;
        private final String deviceToken;
        private final List<String> preferredChannels;

        public User(String id, String name, String email, String phone,
                    String deviceToken, List<String> preferredChannels) {
            this.id = Objects.requireNonNull(id);
            this.name = Objects.requireNonNull(name);
            this.email = email;
            this.phone = phone;
            this.deviceToken = deviceToken;
            this.preferredChannels = List.copyOf(preferredChannels);
        }

        public String getId() { return id; }
        public String getName() { return name; }
        public String getEmail() { return email; }
        public String getPhone() { return phone; }
        public String getDeviceToken() { return deviceToken; }
        public List<String> getPreferredChannels() { return preferredChannels; }
    }

    public static final class Notification {
        private final String id;
        private final String type;
        private final String subject;
        private final String body;
        private final Map<String, String> metadata;

        public Notification(String id, String type, String subject, String body,
                            Map<String, String> metadata) {
            this.id = Objects.requireNonNull(id);
            this.type = Objects.requireNonNull(type);
            this.subject = subject;
            this.body = Objects.requireNonNull(body);
            this.metadata = metadata == null ? Map.of() : Map.copyOf(metadata);
        }

        public String getId() { return id; }
        public String getType() { return type; }
        public String getSubject() { return subject; }
        public String getBody() { return body; }
        public Map<String, String> getMetadata() { return metadata; }
    }

    public static final class DeliveryResult {
        private final String channel;
        private final DeliveryStatus status;
        private final String errorMessage;

        public DeliveryResult(String channel, DeliveryStatus status, String errorMessage) {
            this.channel = channel;
            this.status = status;
            this.errorMessage = errorMessage;
        }

        public String getChannel() { return channel; }
        public DeliveryStatus getStatus() { return status; }
        public String getErrorMessage() { return errorMessage; }
    }

    public static final class NotificationRecord {
        private final long id;
        private final String userId;
        private final String notificationId;
        private final String channel;
        private final DeliveryStatus status;
        private final long timestamp;
        private final String errorMessage;

        public NotificationRecord(long id, String userId, String notificationId,
                                  String channel, DeliveryStatus status,
                                  long timestamp, String errorMessage) {
            this.id = id;
            this.userId = userId;
            this.notificationId = notificationId;
            this.channel = channel;
            this.status = status;
            this.timestamp = timestamp;
            this.errorMessage = errorMessage;
        }

        public long getId() { return id; }
        public String getUserId() { return userId; }
        public String getNotificationId() { return notificationId; }
        public String getChannel() { return channel; }
        public DeliveryStatus getStatus() { return status; }
        public long getTimestamp() { return timestamp; }
        public String getErrorMessage() { return errorMessage; }
    }

    public static final class UserBroadcastResult {
        private final String userId;
        private final int successCount;
        private final int failureCount;
        private final String error;
        public UserBroadcastResult(String userId, int successCount, int failureCount, String error) {
            this.userId = userId; this.successCount = successCount;
            this.failureCount = failureCount; this.error = error;
        }
        public String getUserId() { return userId; }
        public int getSuccessCount() { return successCount; }
        public int getFailureCount() { return failureCount; }
        public String getError() { return error; }
    }

    public static final class BroadcastSummary {
        private final int totalSuccess;
        private final int totalFailure;
        private final List<UserBroadcastResult> details;
        public BroadcastSummary(int totalSuccess, int totalFailure, List<UserBroadcastResult> details) {
            this.totalSuccess = totalSuccess;
            this.totalFailure = totalFailure;
            this.details = List.copyOf(details);
        }
        public int getTotalSuccess() { return totalSuccess; }
        public int getTotalFailure() { return totalFailure; }
        public List<UserBroadcastResult> getDetails() { return details; }
    }

    // ------------------------------------------------------------------
    // Custom exceptions
    // ------------------------------------------------------------------

    public static class NotificationException extends Exception {
        public NotificationException(String message) { super(message); }
        public NotificationException(String message, Throwable cause) { super(message, cause); }
    }

    public static class UnknownUserException extends NotificationException {
        public UnknownUserException(String userId) { super("Unknown user: " + userId); }
    }

    public static class NoChannelsAvailableException extends NotificationException {
        public NoChannelsAvailableException(String userId) {
            super("No channels available for user: " + userId);
        }
    }

    public static class ChannelSendException extends NotificationException {
        public ChannelSendException(String channel, Throwable cause) {
            super("Channel '" + channel + "' failed", cause);
        }
    }

    public static class NotificationTimeoutException extends NotificationException {
        public NotificationTimeoutException(String message, Throwable cause) { super(message, cause); }
    }

    public static class NotificationInterruptedException extends NotificationException {
        public NotificationInterruptedException(String message, Throwable cause) { super(message, cause); }
    }

    // ------------------------------------------------------------------
    // Helper thread factory
    // ------------------------------------------------------------------

    private static final class NamedThreadFactory implements java.util.concurrent.ThreadFactory {
        private final String prefix;
        private final java.util.concurrent.atomic.AtomicInteger counter =
            new java.util.concurrent.atomic.AtomicInteger();
        NamedThreadFactory(String prefix) { this.prefix = prefix; }
        @Override
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, prefix + "-" + counter.incrementAndGet());
            t.setDaemon(true);
            return t;
        }
    }

    // ------------------------------------------------------------------
    // Sample channel implementations (unchanged from legacy version)
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
            System.out.println("EMAIL to=" + user.getEmail()
                + " from=" + fromAddress
                + " subject=" + notification.getSubject()
                + " body=" + notification.getBody().substring(
                    0, Math.min(50, notification.getBody().length())));
        }

        @Override
        public void close() {
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
                + " body=" + notification.getBody().substring(
                    0, Math.min(140, notification.getBody().length())));
        }

        @Override
        public void close() {
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
                + " body=" + notification.getBody().substring(
                    0, Math.min(80, notification.getBody().length())));
        }

        @Override
        public void close() {
            System.out.println("Closing FCM connection");
        }
    }

    // ------------------------------------------------------------------
    // Demo main
    // ------------------------------------------------------------------

    public static void main(String[] args) throws Exception {
        try (NotificationService service = new NotificationService()) {
            service.registerChannel(new EmailChannel("smtp.example.com", 587, "noreply@example.com"));
            service.registerChannel(new SmsChannel("https://sms.example.com/api", "secret"));
            service.registerChannel(new PushChannel("fcm-server-key"));
            service.registerUser(new User("u1", "Alice", "alice@example.com",
                "+15551234567", "device-token-alice",
                List.of("email", "push")));
            Notification n = new Notification("n1", "welcome", "Welcome!",
                "Thanks for signing up. We're glad to have you.",
                Map.of("source", "web"));
            Map<String, DeliveryResult> results = service.sendNotification("u1", n);
            System.out.println("Results: " + results);
            System.out.println("Stats: " + service.getStats());
        }
    }
}
