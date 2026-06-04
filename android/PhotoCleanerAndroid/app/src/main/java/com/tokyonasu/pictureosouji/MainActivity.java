package com.tokyonasu.pictureosouji;

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.IntentSender;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Size;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.GridLayout;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int REQUEST_READ_IMAGES = 100;
    private static final int REQUEST_DELETE_IMAGES = 200;
    private static final int MAX_SCAN_COUNT = 2000;
    private static final int SIMILAR_THRESHOLD = 8;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ArrayList<PhotoGroup> groups = new ArrayList<>();
    private final Set<Uri> selectedForDeletion = new HashSet<>();

    private FrameLayout root;
    private LinearLayout progressBox;
    private ProgressBar progressBar;
    private TextView progressText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        root = new FrameLayout(this);
        setContentView(root);
        showHome();
    }

    private void showHome() {
        selectedForDeletion.clear();
        root.removeAllViews();

        ImageView background = new ImageView(this);
        background.setImageResource(getResources().getIdentifier("top_background", "drawable", getPackageName()));
        background.setScaleType(ImageView.ScaleType.CENTER_CROP);
        root.addView(background, new FrameLayout.LayoutParams(-1, -1));

        View shade = new View(this);
        shade.setBackgroundColor(Color.argb(145, 0, 0, 0));
        root.addView(shade, new FrameLayout.LayoutParams(-1, -1));

        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setGravity(Gravity.START);
        panel.setPadding(dp(24), dp(24), dp(24), dp(26));

        TextView title = text("ピクチャおそうじ", 38, Color.WHITE, true);
        TextView subtitle = text("似ている写真を見つけて、残す1枚を選びやすくします。", 18, Color.argb(235, 255, 255, 255), true);
        subtitle.setPadding(0, dp(8), 0, dp(16));

        TextView bullets = text("・端末内で写真を解析\n・信頼度つきで候補を表示\n・削除前に必ず確認", 14, Color.argb(225, 255, 255, 255), true);
        bullets.setLineSpacing(dp(4), 1.0f);
        bullets.setPadding(0, 0, 0, dp(18));

        Button scanButton = primaryButton("スキャン開始");
        scanButton.setOnClickListener(v -> startScanWithPermission());

        TextView note = text("写真はサーバーへ送りません。削除はAndroidの確認画面を通して行います。", 12, Color.argb(205, 255, 255, 255), false);
        note.setPadding(0, dp(12), 0, 0);

        panel.addView(title);
        panel.addView(subtitle);
        panel.addView(bullets);
        panel.addView(scanButton, new LinearLayout.LayoutParams(-1, dp(54)));
        panel.addView(note);

        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
        root.addView(panel, params);
    }

    private void startScanWithPermission() {
        String permission = Build.VERSION.SDK_INT >= 33
                ? Manifest.permission.READ_MEDIA_IMAGES
                : Manifest.permission.READ_EXTERNAL_STORAGE;

        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            scanPhotos();
        } else {
            requestPermissions(new String[]{permission}, REQUEST_READ_IMAGES);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_READ_IMAGES
                && grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            scanPhotos();
        } else {
            Toast.makeText(this, "写真へのアクセスを許可してください。", Toast.LENGTH_LONG).show();
        }
    }

    private void scanPhotos() {
        showProgress();
        executor.execute(() -> {
            ArrayList<PhotoItem> photos = loadPhotoItems();
            postProgress(45, "特徴を見ています");
            ArrayList<PhotoGroup> result = buildGroups(photos);
            groups.clear();
            groups.addAll(result);
            mainHandler.post(this::showResults);
        });
    }

    private ArrayList<PhotoItem> loadPhotoItems() {
        ArrayList<PhotoItem> items = new ArrayList<>();
        ContentResolver resolver = getContentResolver();
        ArrayList<String> columns = new ArrayList<>();
        columns.add(MediaStore.Images.Media._ID);
        columns.add(MediaStore.Images.Media.DATE_ADDED);
        columns.add(MediaStore.Images.Media.WIDTH);
        columns.add(MediaStore.Images.Media.HEIGHT);
        if (Build.VERSION.SDK_INT >= 30) {
            columns.add(MediaStore.MediaColumns.IS_FAVORITE);
        }

        String[] projection = columns.toArray(new String[0]);
        String sortOrder = MediaStore.Images.Media.DATE_ADDED + " DESC";

        try (Cursor cursor = resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
        )) {
            if (cursor == null) return items;

            int idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID);
            int dateCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED);
            int widthCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH);
            int heightCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT);
            int favoriteCol = Build.VERSION.SDK_INT >= 30
                    ? cursor.getColumnIndex(MediaStore.MediaColumns.IS_FAVORITE)
                    : -1;

            int count = cursor.getCount();
            int index = 0;
            while (cursor.moveToNext() && index < MAX_SCAN_COUNT) {
                long id = cursor.getLong(idCol);
                Uri uri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, String.valueOf(id));
                Bitmap thumbnail = loadThumbnail(uri);
                if (thumbnail != null) {
                    PhotoItem item = new PhotoItem();
                    item.uri = uri;
                    item.dateAdded = cursor.getLong(dateCol);
                    item.width = cursor.getInt(widthCol);
                    item.height = cursor.getInt(heightCol);
                    item.favorite = favoriteCol >= 0 && cursor.getInt(favoriteCol) == 1;
                    item.hash = differenceHash(thumbnail);
                    items.add(item);
                }

                index++;
                if (index % 25 == 0) {
                    int percent = 5 + (int) (40.0 * Math.min(index, count) / Math.max(1, Math.min(count, MAX_SCAN_COUNT)));
                    postProgress(percent, index + "枚を確認中");
                }
            }
        }
        return items;
    }

    private Bitmap loadThumbnail(Uri uri) {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                return getContentResolver().loadThumbnail(uri, new Size(96, 96), null);
            }
            return MediaStore.Images.Media.getBitmap(getContentResolver(), uri);
        } catch (IOException | SecurityException e) {
            return null;
        }
    }

    private ArrayList<PhotoGroup> buildGroups(ArrayList<PhotoItem> photos) {
        postProgress(60, "似ている写真をまとめています");
        int n = photos.size();
        int[] parent = new int[n];
        int[] maxDistance = new int[n];
        for (int i = 0; i < n; i++) parent[i] = i;

        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++) {
                int distance = Long.bitCount(photos.get(i).hash ^ photos.get(j).hash);
                if (distance <= SIMILAR_THRESHOLD) {
                    int rootA = find(parent, i);
                    int rootB = find(parent, j);
                    if (rootA != rootB) parent[rootB] = rootA;
                    int root = find(parent, i);
                    maxDistance[root] = Math.max(maxDistance[root], distance);
                }
            }
            if (i % 50 == 0) {
                int percent = 60 + (int) (30.0 * i / Math.max(1, n));
                postProgress(percent, "類似度を比較中");
            }
        }

        ArrayList<PhotoGroup> result = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            int groupRoot = find(parent, i);
            PhotoGroup group = null;
            for (PhotoGroup existing : result) {
                if (existing.root == groupRoot) {
                    group = existing;
                    break;
                }
            }
            if (group == null) {
                group = new PhotoGroup();
                group.root = groupRoot;
                group.maxDistance = maxDistance[groupRoot];
                result.add(group);
            }
            group.items.add(photos.get(i));
        }

        result.removeIf(group -> group.items.size() < 2);
        for (PhotoGroup group : result) {
            group.items.sort(Comparator.comparingDouble(this::qualityScore).reversed());
            group.recommendedKeep = group.items.get(0);
            if (group.maxDistance == 0) group.maxDistance = estimateMaxDistance(group.items);
        }
        result.sort((a, b) -> {
            int confidence = Integer.compare(a.confidenceRank(), b.confidenceRank());
            if (confidence != 0) return confidence;
            return Integer.compare(b.items.size(), a.items.size());
        });
        postProgress(100, "完了");
        return result;
    }

    private int estimateMaxDistance(List<PhotoItem> items) {
        int max = 0;
        for (int i = 0; i < items.size(); i++) {
            for (int j = i + 1; j < items.size(); j++) {
                max = Math.max(max, Long.bitCount(items.get(i).hash ^ items.get(j).hash));
            }
        }
        return max;
    }

    private int find(int[] parent, int index) {
        while (parent[index] != index) {
            parent[index] = parent[parent[index]];
            index = parent[index];
        }
        return index;
    }

    private long differenceHash(Bitmap source) {
        Bitmap scaled = Bitmap.createScaledBitmap(source, 9, 8, true);
        long hash = 0;
        int bit = 0;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                int left = gray(scaled.getPixel(x, y));
                int right = gray(scaled.getPixel(x + 1, y));
                if (left > right) hash |= (1L << bit);
                bit++;
            }
        }
        return hash;
    }

    private int gray(int color) {
        return (Color.red(color) * 30 + Color.green(color) * 59 + Color.blue(color) * 11) / 100;
    }

    private double qualityScore(PhotoItem item) {
        double pixels = (double) item.width * Math.max(1, item.height);
        double favorite = item.favorite ? 100_000_000.0 : 0;
        return favorite + pixels + item.dateAdded;
    }

    private void showProgress() {
        root.removeAllViews();
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(28), dp(28), dp(28), dp(28));

        progressText = text("写真を確認中", 22, Color.rgb(20, 35, 55), true);
        progressText.setGravity(Gravity.CENTER);
        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(100);
        progressBar.setProgress(0);

        TextView note = text("端末内で処理しています。枚数が多いと少し時間がかかります。", 14, Color.DKGRAY, false);
        note.setGravity(Gravity.CENTER);
        note.setPadding(0, dp(14), 0, 0);

        box.addView(progressText, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(-1, dp(14));
        barParams.setMargins(0, dp(20), 0, 0);
        box.addView(progressBar, barParams);
        box.addView(note);

        progressBox = box;
        root.addView(box, new FrameLayout.LayoutParams(-1, -1));
    }

    private void postProgress(int percent, String label) {
        mainHandler.post(() -> {
            if (progressBar != null) progressBar.setProgress(percent);
            if (progressText != null) progressText.setText(label + "  " + percent + "%");
        });
    }

    private void showResults() {
        root.removeAllViews();
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(Color.rgb(244, 248, 250));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(18), dp(18), dp(18), dp(12));
        header.setBackgroundColor(Color.WHITE);

        TextView title = text(groups.size() + "グループ", 24, Color.rgb(20, 35, 55), true);
        String subtitleText = groups.isEmpty()
                ? "類似写真は見つかりませんでした。"
                : "類似写真が見つかりました。削除前に見比べてください。";
        TextView subtitle = text(subtitleText, 14, Color.DKGRAY, false);
        subtitle.setPadding(0, dp(4), 0, 0);
        header.addView(title);
        header.addView(subtitle);
        page.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(14), dp(12), dp(14), dp(90));
        scroll.addView(list);
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        if (groups.isEmpty()) {
            Button retry = secondaryButton("もう一度スキャン");
            retry.setOnClickListener(v -> scanPhotos());
            list.addView(retry, new LinearLayout.LayoutParams(-1, dp(52)));
        } else {
            for (PhotoGroup group : groups) {
                list.addView(groupRow(group));
            }
        }

        Button deleteButton = primaryButton("選択した写真を削除");
        deleteButton.setOnClickListener(v -> requestDeleteSelected());
        page.addView(deleteButton, new LinearLayout.LayoutParams(-1, dp(56)));

        root.addView(page);
    }

    private View groupRow(PhotoGroup group) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.VERTICAL);
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setBackgroundColor(Color.WHITE);

        TextView title = text(group.items.size() + "枚の類似写真", 18, Color.rgb(20, 35, 55), true);
        TextView sub = text(group.confidenceLabel() + " / 最大距離 " + group.maxDistance, 13, group.confidenceColor(), true);
        sub.setPadding(0, dp(3), 0, dp(10));

        LinearLayout thumbs = new LinearLayout(this);
        thumbs.setOrientation(LinearLayout.HORIZONTAL);
        int shown = Math.min(4, group.items.size());
        for (int i = 0; i < shown; i++) {
            ImageView image = new ImageView(this);
            image.setScaleType(ImageView.ScaleType.CENTER_CROP);
            try {
                image.setImageBitmap(getContentResolver().loadThumbnail(group.items.get(i).uri, new Size(96, 96), null));
            } catch (Exception ignored) {
                image.setBackgroundColor(Color.LTGRAY);
            }
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(58), dp(58));
            params.setMargins(0, 0, dp(8), 0);
            thumbs.addView(image, params);
        }

        Button open = secondaryButton("確認する");
        open.setOnClickListener(v -> showGroup(group));

        row.addView(title);
        row.addView(sub);
        row.addView(thumbs);
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(-1, dp(46));
        buttonParams.setMargins(0, dp(10), 0, 0);
        row.addView(open, buttonParams);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, 0, 0, dp(12));
        row.setLayoutParams(params);
        return row;
    }

    private void showGroup(PhotoGroup group) {
        root.removeAllViews();
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(Color.rgb(244, 248, 250));

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(dp(14), dp(14), dp(14), dp(10));
        header.setBackgroundColor(Color.WHITE);

        Button back = secondaryButton("戻る");
        back.setOnClickListener(v -> showResults());
        TextView title = text(group.items.size() + "枚の類似写真", 22, Color.rgb(20, 35, 55), true);
        TextView note = text(group.confidenceLabel() + "。残す候補を確認してから選んでください。", 13, Color.DKGRAY, false);
        note.setPadding(0, dp(4), 0, 0);
        header.addView(back, new LinearLayout.LayoutParams(-1, dp(44)));
        header.addView(title);
        header.addView(note);
        page.addView(header);

        ScrollView scroll = new ScrollView(this);
        GridLayout grid = new GridLayout(this);
        grid.setColumnCount(3);
        grid.setPadding(dp(4), dp(4), dp(4), dp(90));
        scroll.addView(grid);

        int cell = getResources().getDisplayMetrics().widthPixels / 3 - dp(6);
        for (PhotoItem item : group.items) {
            FrameLayout cellView = photoCell(item, group.recommendedKeep == item, cell);
            grid.addView(cellView);
        }
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setPadding(dp(8), dp(8), dp(8), dp(8));
        actions.setBackgroundColor(Color.WHITE);

        Button selectRecommended = primaryButton("おすすめ以外");
        selectRecommended.setOnClickListener(v -> {
            for (PhotoItem item : group.items) {
                if (item != group.recommendedKeep) selectedForDeletion.add(item.uri);
            }
            showGroup(group);
        });
        Button clear = secondaryButton("解除");
        clear.setOnClickListener(v -> {
            for (PhotoItem item : group.items) selectedForDeletion.remove(item.uri);
            showGroup(group);
        });
        actions.addView(selectRecommended, new LinearLayout.LayoutParams(0, dp(52), 1));
        actions.addView(clear, new LinearLayout.LayoutParams(0, dp(52), 1));
        page.addView(actions);

        root.addView(page);
    }

    private FrameLayout photoCell(PhotoItem item, boolean recommended, int size) {
        FrameLayout frame = new FrameLayout(this);
        GridLayout.LayoutParams params = new GridLayout.LayoutParams();
        params.width = size;
        params.height = size;
        params.setMargins(dp(2), dp(2), dp(2), dp(2));
        frame.setLayoutParams(params);

        ImageView image = new ImageView(this);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP);
        try {
            image.setImageBitmap(getContentResolver().loadThumbnail(item.uri, new Size(240, 240), null));
        } catch (Exception ignored) {
            image.setBackgroundColor(Color.LTGRAY);
        }
        frame.addView(image, new FrameLayout.LayoutParams(-1, -1));

        if (recommended) {
            TextView badge = text("残す候補", 11, Color.WHITE, true);
            badge.setBackgroundColor(Color.rgb(16, 132, 91));
            badge.setPadding(dp(6), dp(3), dp(6), dp(3));
            FrameLayout.LayoutParams badgeParams = new FrameLayout.LayoutParams(-2, -2, Gravity.START | Gravity.TOP);
            badgeParams.setMargins(dp(5), dp(5), 0, 0);
            frame.addView(badge, badgeParams);
        }

        ImageButton check = new ImageButton(this);
        boolean selected = selectedForDeletion.contains(item.uri);
        check.setImageResource(selected ? android.R.drawable.checkbox_on_background : android.R.drawable.checkbox_off_background);
        check.setBackgroundColor(Color.TRANSPARENT);
        check.setOnClickListener(v -> {
            if (selectedForDeletion.contains(item.uri)) selectedForDeletion.remove(item.uri);
            else selectedForDeletion.add(item.uri);
            showGroup(findGroupFor(item));
        });
        FrameLayout.LayoutParams checkParams = new FrameLayout.LayoutParams(dp(44), dp(44), Gravity.END | Gravity.TOP);
        frame.addView(check, checkParams);
        return frame;
    }

    private PhotoGroup findGroupFor(PhotoItem item) {
        for (PhotoGroup group : groups) {
            if (group.items.contains(item)) return group;
        }
        return groups.isEmpty() ? new PhotoGroup() : groups.get(0);
    }

    private void requestDeleteSelected() {
        if (selectedForDeletion.isEmpty()) {
            Toast.makeText(this, "削除する写真を選んでください。", Toast.LENGTH_SHORT).show();
            return;
        }

        ArrayList<Uri> uris = new ArrayList<>(selectedForDeletion);
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                PendingIntent pendingIntent = MediaStore.createDeleteRequest(getContentResolver(), uris);
                startIntentSenderForResult(
                        pendingIntent.getIntentSender(),
                        REQUEST_DELETE_IMAGES,
                        null,
                        0,
                        0,
                        0
                );
            } catch (IntentSender.SendIntentException e) {
                Toast.makeText(this, "削除確認を開けませんでした。", Toast.LENGTH_LONG).show();
            }
        } else {
            int deleted = 0;
            for (Uri uri : uris) {
                deleted += getContentResolver().delete(uri, null, null);
            }
            Toast.makeText(this, deleted + "枚を削除しました。", Toast.LENGTH_LONG).show();
            selectedForDeletion.clear();
            scanPhotos();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_DELETE_IMAGES) {
            if (resultCode == RESULT_OK) {
                Toast.makeText(this, "削除しました。", Toast.LENGTH_LONG).show();
                selectedForDeletion.clear();
                scanPhotos();
            } else {
                Toast.makeText(this, "削除をキャンセルしました。", Toast.LENGTH_SHORT).show();
            }
        }
    }

    private TextView text(String value, int sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private Button primaryButton(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(Color.WHITE);
        button.setTextSize(16);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackgroundColor(Color.rgb(16, 132, 91));
        return button;
    }

    private Button secondaryButton(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(Color.rgb(8, 84, 165));
        button.setTextSize(15);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackgroundColor(Color.rgb(229, 238, 247));
        return button;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static class PhotoItem {
        Uri uri;
        long hash;
        long dateAdded;
        int width;
        int height;
        boolean favorite;
    }

    private static class PhotoGroup {
        int root;
        int maxDistance;
        PhotoItem recommendedKeep;
        ArrayList<PhotoItem> items = new ArrayList<>();

        int confidenceRank() {
            if (maxDistance <= 4) return 0;
            if (maxDistance <= 8) return 1;
            return 2;
        }

        String confidenceLabel() {
            if (maxDistance <= 4) return "かなり近い";
            if (maxDistance <= 8) return "似ている";
            return "要確認";
        }

        int confidenceColor() {
            if (maxDistance <= 4) return Color.rgb(16, 132, 91);
            if (maxDistance <= 8) return Color.rgb(8, 84, 165);
            return Color.rgb(196, 112, 22);
        }
    }
}
