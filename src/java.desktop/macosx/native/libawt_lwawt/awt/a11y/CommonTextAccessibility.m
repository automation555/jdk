/*
 * Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

#import "CommonTextAccessibility.h"
#import "ThreadUtilities.h"
#import "JNIUtilities.h"

#define DEFAULT_RANGE NSMakeRange(0, 0)
#define DEFAULT_RECT NSMakeRect(0, 0, 0, 0)

static jclass sjc_CAccessibility = NULL;
static jmethodID sjm_getAccessibleText = NULL;
#define GET_ACCESSIBLETEXT_METHOD_RETURN(ret) \
    GET_CACCESSIBILITY_CLASS_RETURN(ret); \
    GET_STATIC_METHOD_RETURN(sjm_getAccessibleText, sjc_CAccessibility, "getAccessibleText", \
              "(Ljavax/accessibility/Accessible;Ljava/awt/Component;)Ljavax/accessibility/AccessibleText;", ret);

static jclass sjc_CAccessibleText = NULL;
#define GET_CACCESSIBLETEXT_CLASS() \
    GET_CLASS(sjc_CAccessibleText, "sun/lwawt/macosx/CAccessibleText");
#define GET_CACCESSIBLETEXT_CLASS_RETURN(ret) \
    GET_CLASS_RETURN(sjc_CAccessibleText, "sun/lwawt/macosx/CAccessibleText", ret);

static jmethodID sjm_getAccessibleEditableText = NULL;
#define GET_ACCESSIBLEEDITABLETEXT_METHOD_RETURN(ret) \
    GET_CACCESSIBLETEXT_CLASS_RETURN(ret); \
    GET_STATIC_METHOD_RETURN(sjm_getAccessibleEditableText, sjc_CAccessibleText, "getAccessibleEditableText", \
              "(Ljavax/accessibility/Accessible;Ljava/awt/Component;)Ljavax/accessibility/AccessibleEditableText;", ret);

/*
 * Converts an int array to an NSRange wrapped inside an NSValue
 * takes [start, end] values and returns [start, end - start]
 */
static NSRange javaIntArrayToNSRange(JNIEnv* env, jintArray array) {
    jint *values = (*env)->GetIntArrayElements(env, array, 0);
    if (values == NULL) {
        NSLog(@"%s failed calling GetIntArrayElements", __FUNCTION__);
        return DEFAULT_RANGE;
    };
    return NSMakeRange(values[0], values[1] - values[0]);
}

@implementation CommonTextAccessibility

- (nullable NSString *)accessibilityValueAttribute
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBILITY_CLASS_RETURN(nil);
    DECLARE_STATIC_METHOD_RETURN(sjm_getAccessibleName, sjc_CAccessibility, "getAccessibleName",
                          "(Ljavax/accessibility/Accessible;Ljava/awt/Component;)Ljava/lang/String;", nil);
    if ([[self accessibilityRoleAttribute] isEqualToString:NSAccessibilityStaticTextRole]) {
        jobject axName = (*env)->CallStaticObjectMethod(env, sjc_CAccessibility,
                           sjm_getAccessibleName, fAccessible, fComponent);
        CHECK_EXCEPTION();
        if (axName != NULL) {
            NSString* str = JavaStringToNSString(env, axName);
            (*env)->DeleteLocalRef(env, axName);
            return str;
        }
        // value is still nil if no accessibleName for static text. Below, try to get the accessibleText.
    }

    GET_ACCESSIBLETEXT_METHOD_RETURN(@"");
    jobject axText = (*env)->CallStaticObjectMethod(env, sjc_CAccessibility,
                      sjm_getAccessibleText, fAccessible, fComponent);
    CHECK_EXCEPTION();
    if (axText == NULL) return nil;
    (*env)->DeleteLocalRef(env, axText);

    GET_ACCESSIBLEEDITABLETEXT_METHOD_RETURN(nil);
    jobject axEditableText = (*env)->CallStaticObjectMethod(env, sjc_CAccessibleText,
                       sjm_getAccessibleEditableText, fAccessible, fComponent);
    CHECK_EXCEPTION();
    if (axEditableText == NULL) return nil;

    DECLARE_STATIC_METHOD_RETURN(jm_getTextRange, sjc_CAccessibleText, "getTextRange",
                    "(Ljavax/accessibility/AccessibleEditableText;IILjava/awt/Component;)Ljava/lang/String;", nil);
    jobject jrange = (*env)->CallStaticObjectMethod(env, sjc_CAccessibleText, jm_getTextRange,
                       axEditableText, 0, getAxTextCharCount(env, axEditableText, fComponent), fComponent);
    CHECK_EXCEPTION();
    NSString *string = JavaStringToNSString(env, jrange);

    (*env)->DeleteLocalRef(env, jrange);
    (*env)->DeleteLocalRef(env, axEditableText);

    if (string == nil) string = @"";
    return string;
}

- (NSRange)accessibilityVisibleCharacterRangeAttribute
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(DEFAULT_RANGE);
    DECLARE_STATIC_METHOD_RETURN(jm_getVisibleCharacterRange, sjc_CAccessibleText, "getVisibleCharacterRange",
                          "(Ljavax/accessibility/Accessible;Ljava/awt/Component;)[I", DEFAULT_RANGE);
    jintArray axTextRange = (*env)->CallStaticObjectMethod(env, sjc_CAccessibleText,
                 jm_getVisibleCharacterRange, fAccessible, fComponent);
    CHECK_EXCEPTION();
    if (axTextRange == NULL) return DEFAULT_RANGE;

    return javaIntArrayToNSRange(env, axTextRange);
}

- (nullable NSString *)accessibilityStringForRangeAttribute:(NSRange)range
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(nil);
    DECLARE_STATIC_METHOD_RETURN(jm_getStringForRange, sjc_CAccessibleText, "getStringForRange",
                 "(Ljavax/accessibility/Accessible;Ljava/awt/Component;II)Ljava/lang/String;", nil);
    jstring jstringForRange = (jstring)(*env)->CallStaticObjectMethod(env, sjc_CAccessibleText, jm_getStringForRange,
                            fAccessible, fComponent, range.location, range.length);
    CHECK_EXCEPTION();
    if (jstringForRange == NULL) return @"";
    NSString* str = JavaStringToNSString(env, jstringForRange);
    (*env)->DeleteLocalRef(env, jstringForRange);
    return str;
}

- (NSRect)accessibilityBoundsForRangeAttribute:(NSRange)range
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(DEFAULT_RECT);
    DECLARE_STATIC_METHOD_RETURN(jm_getBoundsForRange, sjc_CAccessibleText, "getBoundsForRange",
                         "(Ljavax/accessibility/Accessible;Ljava/awt/Component;II)[D", NSMakeRect(0, 0, 0, 0));
    jdoubleArray axBounds = (jdoubleArray)(*env)->CallStaticObjectMethod(env, sjc_CAccessibleText, jm_getBoundsForRange,
                              fAccessible, fComponent, range.location, range.length);
    CHECK_EXCEPTION();
    if (axBounds == NULL) return DEFAULT_RECT;

    jdouble *values = (*env)->GetDoubleArrayElements(env, axBounds, 0);
    CHECK_EXCEPTION();
    if (values == NULL) {
        NSLog(@"%s failed calling GetDoubleArrayElements", __FUNCTION__);
        return DEFAULT_RECT;
    };
    NSRect bounds;
    bounds.origin.x = values[0];
    bounds.origin.y = [[[[self view] window] screen] frame].size.height - values[1] - values[3];
    bounds.size.width = values[2];
    bounds.size.height = values[3];
    return bounds;
}

- (int)accessibilityLineForIndexAttribute:(int)index
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(-1);
    DECLARE_STATIC_METHOD_RETURN(jm_getLineNumberForIndex, sjc_CAccessibleText, "getLineNumberForIndex",
                           "(Ljavax/accessibility/Accessible;Ljava/awt/Component;I)I", -1);
    jint row = (*env)->CallStaticIntMethod(env, sjc_CAccessibleText, jm_getLineNumberForIndex,
                       fAccessible, fComponent, index);
    CHECK_EXCEPTION();
    return row;
}

- (NSRange)accessibilityRangeForLineAttribute:(int)index
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(DEFAULT_RANGE);
    DECLARE_STATIC_METHOD_RETURN(jm_getRangeForLine, sjc_CAccessibleText, "getRangeForLine",
                 "(Ljavax/accessibility/Accessible;Ljava/awt/Component;I)[I", DEFAULT_RANGE);
    jintArray axTextRange = (jintArray)(*env)->CallStaticObjectMethod(env, sjc_CAccessibleText,
                jm_getRangeForLine, fAccessible, fComponent, index);
    CHECK_EXCEPTION();
    if (axTextRange == NULL) return DEFAULT_RANGE;

    return javaIntArrayToNSRange(env,axTextRange);
}

- (NSRange)accessibilityRangeForPositionAttribute:(NSPoint)point
{

    point.y = [[[[self view] window] screen] frame].size.height - point.y; // flip into java screen coords (0 is at upper-left corner of screen)

    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(DEFAULT_RANGE);
    DECLARE_STATIC_METHOD_RETURN(jm_getCharacterIndexAtPosition, sjc_CAccessibleText, "getCharacterIndexAtPosition",
                           "(Ljavax/accessibility/Accessible;Ljava/awt/Component;II)I", DEFAULT_RANGE);
    jint charIndex = (*env)->CallStaticIntMethod(env, sjc_CAccessibleText, jm_getCharacterIndexAtPosition,
                            fAccessible, fComponent, point.x, point.y);
    CHECK_EXCEPTION();
    if (charIndex == -1) return DEFAULT_RANGE;

    // AccessibleText.getIndexAtPoint returns -1 for an invalid point
    return NSMakeRange(charIndex, 1); //range's length is 1 - one-character range
}

- (NSRange)accessibilityRangeForIndexAttribute:(int)index
{
    JNIEnv *env = [ThreadUtilities getJNIEnv];
    GET_CACCESSIBLETEXT_CLASS_RETURN(DEFAULT_RANGE);
    DECLARE_STATIC_METHOD_RETURN(jm_getRangeForIndex, sjc_CAccessibleText, "getRangeForIndex",
                    "(Ljavax/accessibility/Accessible;Ljava/awt/Component;I)[I", DEFAULT_RANGE);
    jintArray axTextRange = (jintArray)(*env)->CallStaticObjectMethod(env, sjc_CAccessibleText, jm_getRangeForIndex,
                              fAccessible, fComponent, index);
    CHECK_EXCEPTION();
    if (axTextRange == NULL) return DEFAULT_RANGE;

    return javaIntArrayToNSRange(env, axTextRange);
}

@end
