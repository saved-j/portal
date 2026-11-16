// JNI bridge: the JVM resolves `external fun XrayStart` to the mangled name below, so the
// c-shared library has to expose exactly these three. The Go side stays a plain C API.
//
// The class is com.follow.clashx.plugins.XrayPlugin, so the mangling is
// Java_com_follow_clashx_plugins_XrayPlugin_<method>. Underscores in a name are escaped as
// _1 by JNI; none of these names contain one.
#include <jni.h>
#include <stdlib.h>
#include <android/log.h>

extern char *XrayStart(char *configJSON, int tunFd, char *assetDir);
extern void XrayStop(void);
extern char *XrayVersion(void);
extern char *XrayMeasure(char *configJSON, char *tagsJSON, char *url, int timeoutMs, int limit);
extern void XrayMeasureStop(void);

// Every line the library logs goes through here: an app process has no console, and Android
// attributes a native line to logcat only through liblog. Called from main.go for the facts
// found before the core exists (which descriptor was handed over, and what it turned out to be).
void libxray_log(const char *message) {
    __android_log_write(ANDROID_LOG_INFO, "libxray", message);
}

static jstring take_error(JNIEnv *env, char *message) {
    if (message == NULL) return NULL;
    jstring out = (*env)->NewStringUTF(env, message);
    free(message);
    return out;
}

JNIEXPORT jstring JNICALL
Java_com_follow_clashx_plugins_XrayPlugin_XrayStart(JNIEnv *env, jobject thiz, jstring config,
                                                    jint tunFd, jstring assetDir) {
    (void) thiz;
    if (config == NULL) return (*env)->NewStringUTF(env, "no config was passed");
    const char *text = (*env)->GetStringUTFChars(env, config, NULL);
    if (text == NULL) return (*env)->NewStringUTF(env, "the config could not be read");
    const char *assets = NULL;
    if (assetDir != NULL) assets = (*env)->GetStringUTFChars(env, assetDir, NULL);
    char *error = XrayStart((char *) text, (int) tunFd, (char *) assets);
    if (assets != NULL) (*env)->ReleaseStringUTFChars(env, assetDir, assets);
    (*env)->ReleaseStringUTFChars(env, config, text);
    return take_error(env, error);
}

JNIEXPORT void JNICALL
Java_com_follow_clashx_plugins_XrayPlugin_XrayStop(JNIEnv *env, jobject thiz) {
    (void) env;
    (void) thiz;
    XrayStop();
}

JNIEXPORT jstring JNICALL
Java_com_follow_clashx_plugins_XrayPlugin_XrayVersion(JNIEnv *env, jobject thiz) {
    (void) thiz;
    return take_error(env, XrayVersion());
}

// One sweep: the document holds the outbounds, the tags name the nodes to time. The whole
// answer comes back as JSON — the sweep is short, and a stream would need a callback the
// plugin's channel does not have.
JNIEXPORT jstring JNICALL
Java_com_follow_clashx_plugins_XrayPlugin_XrayMeasure(JNIEnv *env, jobject thiz, jstring config,
                                                      jstring tags, jstring url, jint timeoutMs,
                                                      jint limit) {
    (void) thiz;
    if (config == NULL || tags == NULL) {
        return (*env)->NewStringUTF(env, "{\"error\":\"no document or no tags\"}");
    }
    const char *text = (*env)->GetStringUTFChars(env, config, NULL);
    if (text == NULL) {
        return (*env)->NewStringUTF(env, "{\"error\":\"the document could not be read\"}");
    }
    const char *names = (*env)->GetStringUTFChars(env, tags, NULL);
    if (names == NULL) {
        (*env)->ReleaseStringUTFChars(env, config, text);
        return (*env)->NewStringUTF(env, "{\"error\":\"the tags could not be read\"}");
    }
    const char *target = NULL;
    // Whether `target` is JNI memory that must be released, as opposed to the literal fallback:
    // an empty URL is a valid string, and skipping its release would leak it every sweep.
    int targetOwned = 0;
    if (url != NULL) {
        target = (*env)->GetStringUTFChars(env, url, NULL);
        // A URL that cannot be read is still a sweep: the core falls back to its own default,
        // so this is not an error, only an empty string.
        if (target == NULL) {
            target = "";
        } else {
            targetOwned = 1;
        }
    }
    char *answer = XrayMeasure((char *) text, (char *) names, (char *) target, (int) timeoutMs, (int) limit);
    if (targetOwned) (*env)->ReleaseStringUTFChars(env, url, target);
    (*env)->ReleaseStringUTFChars(env, tags, names);
    (*env)->ReleaseStringUTFChars(env, config, text);
    if (answer == NULL) return (*env)->NewStringUTF(env, "{\"error\":\"no answer\"}");
    jstring out = (*env)->NewStringUTF(env, answer);
    free(answer);
    return out;
}

JNIEXPORT void JNICALL
Java_com_follow_clashx_plugins_XrayPlugin_XrayMeasureStop(JNIEnv *env, jobject thiz) {
    (void) env;
    (void) thiz;
    XrayMeasureStop();
}
