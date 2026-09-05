package at.uac.android;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsProvider;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/** Framework/Java only: this test-APK provider also starts outside instrumentation's classloader. */
public final class PhotoFixtureDocumentsProvider extends DocumentsProvider {
    private static final String TARGET = "at.uac.android.local";
    private static final String TEST = "at.uac.android.local.test";
    private static final String AUTHORITY = TEST + ".photo_documents";
    private static final String ROOT = "uac-synthetic";
    private static final String TITLE = "UAC synthetic";
    private static final int MAX_BYTES = 32768;
    private static final Pattern ALBUM = Pattern.compile("[A-Za-z0-9-]{1,33}");
    private static final Object LOCK = new Object();
    private static final String[] ROOT_COLUMNS = {
        DocumentsContract.Root.COLUMN_ROOT_ID, DocumentsContract.Root.COLUMN_DOCUMENT_ID,
        DocumentsContract.Root.COLUMN_TITLE, DocumentsContract.Root.COLUMN_FLAGS,
        DocumentsContract.Root.COLUMN_MIME_TYPES
    };
    private static final String[] DOCUMENT_COLUMNS = {
        DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_FLAGS,
        DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED
    };

    @Override public boolean onCreate() { return true; }

    @Override public Cursor queryRoots(String[] projection) throws FileNotFoundException {
        MatrixCursor cursor = new MatrixCursor(projection == null ? ROOT_COLUMNS : projection);
        synchronized (LOCK) {
            if (isLocalProvider(getContext()) && current(getContext()) != null) {
                cursor.newRow().add(DocumentsContract.Root.COLUMN_ROOT_ID, ROOT)
                    .add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, ROOT)
                    .add(DocumentsContract.Root.COLUMN_TITLE, TITLE)
                    .add(DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.FLAG_LOCAL_ONLY)
                    .add(DocumentsContract.Root.COLUMN_MIME_TYPES, "image/png");
            }
        }
        return cursor;
    }

    @Override public Cursor queryDocument(String documentId, String[] projection)
            throws FileNotFoundException {
        synchronized (LOCK) {
            requireLocalProvider(getContext());
            MatrixCursor cursor = documents(projection);
            if (ROOT.equals(documentId)) {
                cursor.newRow().add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, ROOT)
                    .add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, TITLE)
                    .add(DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.MIME_TYPE_DIR)
                    .add(DocumentsContract.Document.COLUMN_FLAGS, 0);
            } else {
                addDocument(cursor, requireDocument(getContext(), documentId));
            }
            return cursor;
        }
    }

    @Override public Cursor queryChildDocuments(String parentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        synchronized (LOCK) {
            requireLocalProvider(getContext());
            if (!ROOT.equals(parentId)) throw new FileNotFoundException("Unknown synthetic root");
            MatrixCursor cursor = documents(projection);
            File file = current(getContext());
            if (file != null) addDocument(cursor, file);
            return cursor;
        }
    }

    @Override public ParcelFileDescriptor openDocument(String documentId, String mode,
            CancellationSignal signal) throws FileNotFoundException {
        synchronized (LOCK) {
            requireLocalProvider(getContext());
            if (!"r".equals(mode)) throw new FileNotFoundException("Read-only synthetic document");
            if (signal != null) signal.throwIfCanceled();
            return ParcelFileDescriptor.open(requireDocument(getContext(), documentId),
                ParcelFileDescriptor.MODE_READ_ONLY);
        }
    }

    private static MatrixCursor documents(String[] projection) {
        return new MatrixCursor(projection == null ? DOCUMENT_COLUMNS : projection);
    }

    private static void addDocument(MatrixCursor cursor, File file) {
        String id = file.getName().substring(0, file.getName().length() - 4);
        cursor.newRow().add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, id)
            .add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, id.substring(37) + ".png")
            .add(DocumentsContract.Document.COLUMN_MIME_TYPE, "image/png")
            .add(DocumentsContract.Document.COLUMN_FLAGS, 0)
            .add(DocumentsContract.Document.COLUMN_SIZE, file.length())
            .add(DocumentsContract.Document.COLUMN_LAST_MODIFIED, file.lastModified());
    }

    private static boolean isLocalProvider(Context context) {
        return context != null && TEST.equals(context.getPackageName())
            && Build.VERSION.SDK_INT == 26 && "ranchu".equals(Build.HARDWARE)
            && "Android SDK built for arm64".equals(Build.MODEL)
            && (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    private static void requireLocalProvider(Context context) {
        if (!isLocalProvider(context)) throw new SecurityException("Local API26 test provider only");
    }

    private static File directory(Context context) throws FileNotFoundException {
        File directory = new File(context.getCacheDir(), "uac-photo-fixture-v1");
        if (!directory.isDirectory() && !directory.mkdir())
            throw new FileNotFoundException("Synthetic fixture cache unavailable");
        return directory;
    }

    private static String id(String token, String album) {
        if (token == null || !UUID.fromString(token).toString().equals(token)
                || album == null || !ALBUM.matcher(album).matches())
            throw new IllegalArgumentException("Invalid synthetic capability");
        return token + "_" + album;
    }

    private static File ownedFile(Context context, String documentId) throws FileNotFoundException {
        if (documentId == null || documentId.length() < 38 || documentId.charAt(36) != '_')
            throw new FileNotFoundException("Unknown synthetic document");
        try { id(documentId.substring(0, 36), documentId.substring(37)); }
        catch (IllegalArgumentException failure) {
            throw new FileNotFoundException("Malformed synthetic document");
        }
        return new File(directory(context), documentId + ".png");
    }

    private static File current(Context context) throws FileNotFoundException {
        File[] files = directory(context).listFiles();
        if (files == null) throw new FileNotFoundException("Synthetic cache unreadable");
        if (files.length == 0) return null;
        if (files.length != 1 || !files[0].getName().endsWith(".png"))
            throw new FileNotFoundException("Unresolved synthetic fixture; explicit cleanup required");
        String name = files[0].getName();
        return requireDocument(context, name.substring(0, name.length() - 4));
    }

    private static File requireDocument(Context context, String documentId)
            throws FileNotFoundException {
        File file = ownedFile(context, documentId);
        if (!file.isFile() || file.length() <= 0 || file.length() > MAX_BYTES)
            throw new FileNotFoundException("Synthetic document missing or invalid");
        return file;
    }

    private static byte[] bytes(File file) throws IOException {
        if (file.length() <= 0 || file.length() > MAX_BYTES) throw new IOException("Invalid PNG size");
        byte[] result = new byte[(int) file.length()];
        try (FileInputStream input = new FileInputStream(file)) {
            int offset = 0;
            while (offset < result.length) {
                int count = input.read(result, offset, result.length - offset);
                if (count < 0) throw new IOException("Truncated synthetic PNG");
                offset += count;
            }
            if (input.read() != -1) throw new IOException("Synthetic PNG changed during read");
        }
        return result;
    }

    private static void validatePng(byte[] png) {
        byte[] signature = {(byte)137, 80, 78, 71, 13, 10, 26, 10};
        if (png == null || png.length < 24 || png.length > MAX_BYTES
                || !Arrays.equals(signature, Arrays.copyOf(png, 8))
                || png[16] != 0 || png[17] != 0 || png[18] != 0 || (png[19] & 255) != 240
                || png[20] != 0 || png[21] != 0 || png[22] != 0 || (png[23] & 255) != 160)
            throw new IllegalArgumentException("Only the bounded synthetic 240x160 PNG is accepted");
    }

    /** Separate test-only call endpoint; DocumentsProvider remains MANAGE_DOCUMENTS protected. */
    public static final class Seeder extends ContentProvider {
        @Override public boolean onCreate() { return true; }

        @Override public Bundle call(String method, String arg, Bundle extras) {
            Context context = getContext();
            requireLocalProvider(context);
            try {
                PackageManager pm = context.getPackageManager();
                ApplicationInfo target = pm.getApplicationInfo(TARGET, 0);
                if (Binder.getCallingUid() != target.uid
                        || (target.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0
                        || pm.checkSignatures(TARGET, TEST) != PackageManager.SIGNATURE_MATCH)
                    throw new SecurityException("Only the signed local target may manage its fixture");
            } catch (PackageManager.NameNotFoundException failure) {
                throw new SecurityException("Local target is unavailable", failure);
            }
            if (arg != null || extras == null || !extras.getBoolean("explicitApi26", false))
                throw new SecurityException("Explicit fixture opt-in required");
            boolean seed = "seed".equals(method);
            if (!seed && !"inspect".equals(method) && !"clear".equals(method))
                throw new SecurityException("Unknown fixture operation");
            Set<String> expected = new HashSet<>(Arrays.asList("token", "album", "explicitApi26"));
            if (seed) expected.add("png");
            if (!extras.keySet().equals(expected)) throw new SecurityException("Unknown fixture fields");
            String documentId = id(extras.getString("token"), extras.getString("album"));
            synchronized (LOCK) {
                try {
                    File file = ownedFile(context, documentId);
                    Bundle result = new Bundle();
                    if (seed) {
                        byte[] png = extras.getByteArray("png");
                        validatePng(png);
                        File[] pending = directory(context).listFiles();
                        if (pending == null || pending.length != 0 || !file.createNewFile())
                            throw new IOException("Previous fixture must be explicitly cleaned first");
                        try (FileOutputStream output = new FileOutputStream(file)) {
                            output.write(png);
                            output.flush();
                            output.getFD().sync();
                        }
                        if (!Arrays.equals(png, bytes(file))) throw new IOException("Seed read-back failed");
                    } else if ("clear".equals(method)) {
                        boolean existed = file.exists();
                        if (existed && !file.delete()) throw new IOException("Exact fixture cleanup failed");
                        if (file.exists()) throw new IOException("Exact fixture still exists");
                        result.putBoolean("removed", existed);
                    }
                    result.putBoolean("present", file.exists());
                    if (file.exists()) result.putByteArray("png", bytes(file));
                    context.getContentResolver().notifyChange(DocumentsContract.buildRootsUri(AUTHORITY), null);
                    return result;
                } catch (IOException failure) {
                    throw new IllegalStateException("Synthetic fixture operation failed", failure);
                }
            }
        }

        @Override public Cursor query(Uri uri, String[] projection, String selection,
                String[] args, String order) { throw new SecurityException("No query surface"); }
        @Override public String getType(Uri uri) { return null; }
        @Override public Uri insert(Uri uri, ContentValues values) { throw new SecurityException("No insert surface"); }
        @Override public int delete(Uri uri, String selection, String[] args) { throw new SecurityException("No delete surface"); }
        @Override public int update(Uri uri, ContentValues values, String selection, String[] args) {
            throw new SecurityException("No update surface");
        }
    }
}
