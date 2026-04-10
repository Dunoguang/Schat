package com.example.rootwebviewdemo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.IBinder;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

public class FloatingOverlayService extends Service {

    private static final String CHANNEL_ID = "floating_overlay_channel";
    private static final int NOTIFICATION_ID = 1002;
    private static final int RESIZE_LEFT = 1;
    private static final int RESIZE_TOP = 1 << 1;
    private static final int RESIZE_RIGHT = 1 << 2;
    private static final int RESIZE_BOTTOM = 1 << 3;

    private WindowManager windowManager;
    private ImageView floatingBallView;
    private FrameLayout webPanelView;
    private WebView overlayWebView;
    private WindowManager.LayoutParams ballParams;
    private WindowManager.LayoutParams panelParams;
    private boolean webPanelVisible;
    private int minPanelWidth;
    private int minPanelHeight;

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        minPanelWidth = dp(280);
        minPanelHeight = dp(320);
        startAsForegroundService();
        createFloatingBall();
        createWebPanel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createFloatingBall() {
        floatingBallView = new ImageView(this);
        int iconPadding = dp(12);
        floatingBallView.setPadding(iconPadding, iconPadding, iconPadding, iconPadding);
        floatingBallView.setImageResource(getApplicationInfo().icon);
        floatingBallView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        floatingBallView.setBackground(buildBallBackground());
        floatingBallView.setElevation(dp(8));

        ballParams = new WindowManager.LayoutParams(
                dp(64),
                dp(64),
                getOverlayType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
        );
        ballParams.gravity = Gravity.TOP | Gravity.START;
        ballParams.x = dp(16);
        ballParams.y = dp(160);

        floatingBallView.setOnTouchListener(new View.OnTouchListener() {
            private int initialX;
            private int initialY;
            private float initialTouchX;
            private float initialTouchY;
            private boolean moved;

            @Override
            public boolean onTouch(View v, MotionEvent event) {
                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = ballParams.x;
                        initialY = ballParams.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        moved = false;
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        int deltaX = (int) (event.getRawX() - initialTouchX);
                        int deltaY = (int) (event.getRawY() - initialTouchY);
                        if (Math.abs(deltaX) > dp(4) || Math.abs(deltaY) > dp(4)) {
                            moved = true;
                        }
                        ballParams.x = initialX + deltaX;
                        ballParams.y = initialY + deltaY;
                        windowManager.updateViewLayout(floatingBallView, ballParams);
                        if (webPanelVisible) {
                            updatePanelPosition();
                        }
                        return true;
                    case MotionEvent.ACTION_UP:
                        if (!moved) {
                            toggleWebPanel();
                        }
                        return true;
                    default:
                        return false;
                }
            }
        });

        windowManager.addView(floatingBallView, ballParams);
    }

    private void createWebPanel() {
        webPanelView = new FrameLayout(this);
        webPanelView.setVisibility(View.GONE);
        webPanelView.setElevation(dp(10));
        webPanelView.setBackground(buildPanelBackground());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webPanelView.setClipToOutline(true);
        }

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(16), dp(12), dp(10), dp(12));
        header.setBackgroundColor(0xFFF5E4EA);

        TextView titleView = new TextView(this);
        titleView.setText(R.string.floating_panel_title);
        titleView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        titleView.setTextColor(0xFF5F3B47);
        titleView.setTypeface(titleView.getTypeface(), android.graphics.Typeface.BOLD);

        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
        );
        header.addView(titleView, titleParams);

        TextView closeButton = new TextView(this);
        closeButton.setText("X");
        closeButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        closeButton.setTextColor(0xFF724651);
        closeButton.setGravity(Gravity.CENTER);
        closeButton.setOnClickListener(v -> closeWebPanel());
        header.addView(closeButton, new LinearLayout.LayoutParams(dp(36), dp(36)));
        bindPanelDrag(titleView);

        overlayWebView = new WebView(this);
        WebSettings settings = overlayWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setDomStorageEnabled(true);
        overlayWebView.setOverScrollMode(View.OVER_SCROLL_NEVER);
        overlayWebView.setWebViewClient(new WebViewClient());
        overlayWebView.addJavascriptInterface(new JsBridge(), "NativeBridge");
        overlayWebView.loadUrl("file:///android_asset/index.html");

        content.addView(header, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
        ));
        content.addView(overlayWebView, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
        ));

        webPanelView.addView(content, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
        ));
        addResizeHandles(webPanelView);

        panelParams = new WindowManager.LayoutParams(
                getPanelWidth(),
                getPanelHeight(),
                getOverlayType(),
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
        );
        panelParams.gravity = Gravity.TOP | Gravity.START;
        updatePanelPosition();

        windowManager.addView(webPanelView, panelParams);
    }

    private void toggleWebPanel() {
        if (webPanelVisible) {
            closeWebPanel();
            return;
        }

        updatePanelPosition();
        webPanelView.setVisibility(View.VISIBLE);
        webPanelVisible = true;
    }

    private void closeWebPanel() {
        webPanelView.setVisibility(View.GONE);
        webPanelVisible = false;
    }

    private void bindPanelDrag(View dragHandle) {
        dragHandle.setOnTouchListener(new View.OnTouchListener() {
            private int initialX;
            private int initialY;
            private float initialTouchX;
            private float initialTouchY;
            private long downAt;
            private boolean dragging;

            @Override
            public boolean onTouch(View v, MotionEvent event) {
                if (panelParams == null) {
                    return false;
                }

                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = panelParams.x;
                        initialY = panelParams.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        downAt = System.currentTimeMillis();
                        dragging = false;
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        if (!dragging) {
                            long pressDuration = System.currentTimeMillis() - downAt;
                            int deltaX = (int) Math.abs(event.getRawX() - initialTouchX);
                            int deltaY = (int) Math.abs(event.getRawY() - initialTouchY);
                            if (pressDuration < 220 || (deltaX < dp(3) && deltaY < dp(3))) {
                                return true;
                            }
                            dragging = true;
                        }

                        panelParams.x = initialX + (int) (event.getRawX() - initialTouchX);
                        panelParams.y = initialY + (int) (event.getRawY() - initialTouchY);
                        constrainPanelToScreen();
                        windowManager.updateViewLayout(webPanelView, panelParams);
                        return true;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        boolean handled = dragging;
                        dragging = false;
                        return handled;
                    default:
                        return false;
                }
            }
        });
    }

    private void addResizeHandles(FrameLayout panelRoot) {
        int edgeSize = dp(18);
        int cornerSize = dp(24);
        addResizeHandle(panelRoot, edgeSize, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.START, RESIZE_LEFT);
        addResizeHandle(panelRoot, edgeSize, FrameLayout.LayoutParams.MATCH_PARENT, Gravity.END, RESIZE_RIGHT);
        addResizeHandle(panelRoot, FrameLayout.LayoutParams.MATCH_PARENT, edgeSize, Gravity.TOP, RESIZE_TOP);
        addResizeHandle(panelRoot, FrameLayout.LayoutParams.MATCH_PARENT, edgeSize, Gravity.BOTTOM, RESIZE_BOTTOM);
        addResizeHandle(panelRoot, cornerSize, cornerSize, Gravity.TOP | Gravity.START, RESIZE_TOP | RESIZE_LEFT);
        addResizeHandle(panelRoot, cornerSize, cornerSize, Gravity.TOP | Gravity.END, RESIZE_TOP | RESIZE_RIGHT);
        addResizeHandle(panelRoot, cornerSize, cornerSize, Gravity.BOTTOM | Gravity.START, RESIZE_BOTTOM | RESIZE_LEFT);
        addResizeHandle(panelRoot, cornerSize, cornerSize, Gravity.BOTTOM | Gravity.END, RESIZE_BOTTOM | RESIZE_RIGHT);
    }

    private void addResizeHandle(FrameLayout panelRoot, int width, int height, int gravity, int edges) {
        View handle = new View(this);
        handle.setBackgroundColor(0x00000000);
        bindPanelResize(handle, edges);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(width, height);
        params.gravity = gravity;
        panelRoot.addView(handle, params);
    }

    private void bindPanelResize(View resizeTarget, int resizeEdges) {
        resizeTarget.setOnTouchListener(new View.OnTouchListener() {
            private int initialX;
            private int initialY;
            private int initialWidth;
            private int initialHeight;
            private float initialTouchX;
            private float initialTouchY;

            @Override
            public boolean onTouch(View v, MotionEvent event) {
                if (panelParams == null) {
                    return false;
                }

                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = panelParams.x;
                        initialY = panelParams.y;
                        initialWidth = panelParams.width;
                        initialHeight = panelParams.height;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        applyPanelResize(
                                event.getRawX(),
                                event.getRawY(),
                                initialTouchX,
                                initialTouchY,
                                initialX,
                                initialY,
                                initialWidth,
                                initialHeight,
                                resizeEdges
                        );
                        return true;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        return true;
                    default:
                        return false;
                }
            }
        });
    }

    private void applyPanelResize(
            float rawX,
            float rawY,
            float startTouchX,
            float startTouchY,
            int startX,
            int startY,
            int startWidth,
            int startHeight,
            int edges
    ) {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int margin = dp(12);
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        int maxWidth = screenWidth - margin * 2;
        int maxHeight = screenHeight - margin * 2;

        int nextX = startX;
        int nextY = startY;
        int nextWidth = startWidth;
        int nextHeight = startHeight;
        int deltaX = Math.round(rawX - startTouchX);
        int deltaY = Math.round(rawY - startTouchY);

        if ((edges & RESIZE_LEFT) != 0) {
            nextX = startX + deltaX;
            nextWidth = startWidth - deltaX;
            if (nextWidth < minPanelWidth) {
                nextWidth = minPanelWidth;
                nextX = startX + (startWidth - minPanelWidth);
            }
            if (nextX < margin) {
                nextX = margin;
                nextWidth = startWidth + (startX - margin);
            }
        }

        if ((edges & RESIZE_RIGHT) != 0) {
            nextWidth = startWidth + deltaX;
            if (nextWidth < minPanelWidth) {
                nextWidth = minPanelWidth;
            }
            if (nextX + nextWidth > screenWidth - margin) {
                nextWidth = screenWidth - margin - nextX;
            }
        }

        if ((edges & RESIZE_TOP) != 0) {
            nextY = startY + deltaY;
            nextHeight = startHeight - deltaY;
            if (nextHeight < minPanelHeight) {
                nextHeight = minPanelHeight;
                nextY = startY + (startHeight - minPanelHeight);
            }
            if (nextY < margin) {
                nextY = margin;
                nextHeight = startHeight + (startY - margin);
            }
        }

        if ((edges & RESIZE_BOTTOM) != 0) {
            nextHeight = startHeight + deltaY;
            if (nextHeight < minPanelHeight) {
                nextHeight = minPanelHeight;
            }
            if (nextY + nextHeight > screenHeight - margin) {
                nextHeight = screenHeight - margin - nextY;
            }
        }

        nextWidth = Math.max(minPanelWidth, Math.min(nextWidth, maxWidth));
        nextHeight = Math.max(minPanelHeight, Math.min(nextHeight, maxHeight));

        if (nextX + nextWidth > screenWidth - margin) {
            nextX = screenWidth - margin - nextWidth;
        }
        if (nextY + nextHeight > screenHeight - margin) {
            nextY = screenHeight - margin - nextHeight;
        }
        nextX = Math.max(margin, nextX);
        nextY = Math.max(margin, nextY);

        panelParams.x = nextX;
        panelParams.y = nextY;
        panelParams.width = nextWidth;
        panelParams.height = nextHeight;
        if (webPanelView.getParent() != null) {
            windowManager.updateViewLayout(webPanelView, panelParams);
        }
    }

    private void updatePanelPosition() {
        if (ballParams == null || panelParams == null) {
            return;
        }

        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int screenWidth = metrics.widthPixels;
        int screenHeight = metrics.heightPixels;
        int margin = dp(12);
        int panelWidth = panelParams.width;
        int panelHeight = panelParams.height;

        int preferredX = ballParams.x + dp(4);
        int maxX = Math.max(margin, screenWidth - panelWidth - margin);
        panelParams.x = Math.min(Math.max(preferredX, margin), maxX);

        int preferredY = ballParams.y + dp(78);
        int maxY = Math.max(margin, screenHeight - panelHeight - margin);
        if (preferredY > maxY) {
            preferredY = ballParams.y - panelHeight - dp(12);
        }
        panelParams.y = Math.min(Math.max(preferredY, margin), maxY);

        if (webPanelView.getParent() != null) {
            windowManager.updateViewLayout(webPanelView, panelParams);
        }
    }

    private void constrainPanelToScreen() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        int margin = dp(12);
        int maxX = Math.max(margin, metrics.widthPixels - panelParams.width - margin);
        int maxY = Math.max(margin, metrics.heightPixels - panelParams.height - margin);
        panelParams.x = Math.min(Math.max(panelParams.x, margin), maxX);
        panelParams.y = Math.min(Math.max(panelParams.y, margin), maxY);
    }

    private GradientDrawable buildBallBackground() {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.OVAL);
        drawable.setColor(0xF7FFFFFF);
        drawable.setStroke(dp(1), 0xFFE6D5DB);
        return drawable;
    }

    private GradientDrawable buildPanelBackground() {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(0xFFFDF8F9);
        drawable.setCornerRadius(dp(22));
        drawable.setStroke(dp(1), 0xFFEACDD5);
        return drawable;
    }

    private int getOverlayType() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
    }

    private int getPanelWidth() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        return Math.min(metrics.widthPixels - dp(24), dp(420));
    }

    private int getPanelHeight() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        return Math.min(metrics.heightPixels - dp(72), dp(620));
    }

    private Notification buildNotification() {
        createNotificationChannel();

        Intent launchIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(getString(R.string.overlay_notification_title))
                .setContentText(getString(R.string.overlay_notification_text))
                .setSmallIcon(android.R.drawable.stat_notify_more)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build();
    }

    private void startAsForegroundService() {
        Notification notification = buildNotification();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            );
            return;
        }
        startForeground(NOTIFICATION_ID, notification);
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }

        NotificationManager notificationManager = getSystemService(NotificationManager.class);
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) {
            return;
        }

        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                getString(R.string.overlay_notification_channel),
                NotificationManager.IMPORTANCE_LOW
        );
        notificationManager.createNotificationChannel(channel);
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value,
                getResources().getDisplayMetrics()
        ));
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (overlayWebView != null) {
            overlayWebView.destroy();
            overlayWebView = null;
        }
        if (webPanelView != null && webPanelView.getParent() != null) {
            windowManager.removeView(webPanelView);
        }
        if (floatingBallView != null && floatingBallView.getParent() != null) {
            windowManager.removeView(floatingBallView);
        }
    }
}
