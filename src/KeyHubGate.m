// KeyHub Gate: optional license overlay for authorized iOS applications.
// iOS 17+, arm64, UIKit + Foundation + Security; no jailbreak frameworks.
// The host IPA must actually load this dylib, and the resulting IPA must be re-signed.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString * const KHBaseURL = @"https://keyhub-api-s6t3.onrender.com/api/v1";
static NSString * const KHKeychainService = @"keyhub.license.injected.v1";
static NSString * const KHLicenseAccount = @"license";
static NSString * const KHDeviceAccount = @"device";

static NSString *KHReadSecret(NSString *account) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: KHKeychainService,
                        (__bridge id)kSecAttrAccount: account,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
static BOOL KHWriteSecret(NSString *account, NSString *value) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: KHKeychainService,
                        (__bridge id)kSecAttrAccount: account};
    SecItemDelete((__bridge CFDictionaryRef)q);
    NSMutableDictionary *item = [q mutableCopy];
    item[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

@interface KHGate : NSObject
@property(nonatomic,strong) UIWindow *gateWindow;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UITextField *licenseField;
@property(nonatomic,strong) UIButton *activationButton;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) BOOL unlocked;
@property(nonatomic,assign) BOOL activationCompleted;
+ (instancetype)shared;
- (void)start;
@end

@implementation KHGate
+ (instancetype)shared {
    static KHGate *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [KHGate new]; });
    return manager;
}

- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self showIfNeeded]; });
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.unlocked = NO;
        [self showIfNeeded];
    });
}

- (UIWindowScene *)foregroundScene {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
    }
    return nil;
}

- (UILabel *)label:(NSString *)text fontSize:(CGFloat)size bold:(BOOL)bold {
    UILabel *l = [UILabel new];
    l.text = text;
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor labelColor];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.numberOfLines = 0;
    return l;
}

- (UITextField *)entry:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *t = [UITextField new];
    t.placeholder = placeholder;
    t.secureTextEntry = secure;
    t.borderStyle = UITextBorderStyleRoundedRect;
    t.backgroundColor = [UIColor secondarySystemBackgroundColor];
    t.font = [UIFont systemFontOfSize:16];
    t.autocorrectionType = UITextAutocorrectionTypeNo;
    t.autocapitalizationType = UITextAutocapitalizationTypeNone;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [t.heightAnchor constraintEqualToConstant:48].active = YES;
    return t;
}

- (void)ensureGateWindow {
    if (self.gateWindow) return;
    UIWindowScene *scene = [self foregroundScene];
    if (!scene) return;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 50;
    window.backgroundColor = [UIColor systemBackgroundColor];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = [UIColor systemBackgroundColor];
    window.rootViewController = root;

    UILabel *title = [self label:@"Kích hoạt KeyHub" fontSize:27 bold:YES];
    UILabel *help = [self label:@"Chỉ cần nhập License Key để kích hoạt ứng dụng. Không cần đăng nhập." fontSize:14 bold:NO];
    help.textColor = [UIColor secondaryLabelColor];
    self.statusLabel = [self label:@"Đang kiểm tra License..." fontSize:14 bold:NO];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.licenseField = [self entry:@"Nhập License Key (IKS-...)" secure:NO];
    self.licenseField.textContentType = UITextContentTypeOneTimeCode;
    UIButton *activate = [UIButton buttonWithType:UIButtonTypeSystem];
    [activate setTitle:@"Kích hoạt" forState:UIControlStateNormal];
    activate.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    activate.backgroundColor = [UIColor systemBlueColor];
    [activate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    activate.layer.cornerRadius = 12;
    [activate.heightAnchor constraintEqualToConstant:50].active = YES;
    [activate addTarget:self action:@selector(activateTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.activationButton = activate;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, help, self.licenseField, activate, self.statusLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.distribution = UIStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.trailingAnchor constant:-22],
        [stack.centerYAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.centerYAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:root.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:root.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];
    self.gateWindow = window;
}

- (void)updateStatus:(NSString *)message {
    self.statusLabel.text = message;
}

- (void)setInputsEnabled:(BOOL)enabled {
    self.licenseField.enabled = enabled;
    self.activationButton.enabled = enabled;
    self.activationButton.alpha = enabled ? 1 : .6;
}

- (void)lockUIWithStatus:(NSString *)status {
    self.unlocked = NO;
    self.gateWindow.hidden = NO;
    [self.gateWindow makeKeyAndVisible];
    [self updateStatus:status];
    [self setInputsEnabled:YES];
}

- (void)unlock {
    self.unlocked = YES;
    self.gateWindow.hidden = YES;
    // Restore focus to the app's window if possible.
    for (UIWindow *window in [self foregroundScene].windows) {
        if (window != self.gateWindow && !window.hidden && window.windowLevel == UIWindowLevelNormal) {
            [window makeKeyWindow];
            break;
        }
    }
}

- (void)showIfNeeded {
    if (self.unlocked || self.busy) return;
    if (![self foregroundScene]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self showIfNeeded]; });
        return;
    }
    [self ensureGateWindow];
    if (!self.gateWindow) return;
    [self.gateWindow makeKeyAndVisible];
    NSString *existingLicense = KHReadSecret(KHLicenseAccount);
    if (existingLicense.length) {
        [self setInputsEnabled:NO];
        [self updateStatus:@"Dang kiem tra License voi may chu..."];
        [self verifyLicense:existingLicense completion:^(BOOL valid, NSString *message) {
            if (valid) [self unlock];
            else [self lockUIWithStatus:message ?: @"Key het han, bi thu hoi hoac khong hop le."];
        }];
    } else {
        [self lockUIWithStatus:@"Chưa kích hoạt. Chỉ cần nhập License Key."];
    }
}

- (void)post:(NSString *)path data:(NSDictionary *)payload
  completion:(void (^)(NSDictionary * _Nullable json, NSString * _Nullable err))completion {
    NSError *serializeError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializeError];
    if (!body) { completion(nil, @"Du lieu khong hop le."); return; }
    NSURL *url = [NSURL URLWithString:[KHBaseURL stringByAppendingString:path]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = @"POST";
    r.HTTPBody = body;
    r.timeoutInterval = 100; // Render free tier may cold-start for 50+ sec.
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:
        ^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSString *failure = nil;
            NSDictionary *json = nil;
            if (error) failure = @"Khong ket noi duoc API. Thu lai khi co mang.";
            if (data.length) {
                id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([obj isKindOfClass:[NSDictionary class]]) json = obj;
            }
            NSInteger code = [(NSHTTPURLResponse *)response statusCode];
            if (!failure && (code < 200 || code >= 300)) {
                id detail = json[@"detail"];
                failure = [detail isKindOfClass:[NSString class]] ? detail :
                    [NSString stringWithFormat:@"May chu tra ve HTTP %ld", (long)code];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(json, failure); });
        }];
    [task resume];
}

- (NSString *)deviceID {
    NSString *saved = KHReadSecret(KHDeviceAccount);
    if (saved.length >= 16) return saved;
    NSString *fresh = [NSUUID UUID].UUIDString;
    return KHWriteSecret(KHDeviceAccount, fresh) ? fresh : nil;
}

- (void)verifyLicense:(NSString *)license completion:(void (^)(BOOL, NSString *))completion {
    if (self.busy) return;
    NSString *device = [self deviceID];
    if (!device.length) { completion(NO, @"Khong the luu Device ID trong Keychain."); return; }
    self.busy = YES;
    [self post:@"/keys/verify" data:@{@"key":license, @"device_id":device, @"label":@"iPhone"}
      completion:^(NSDictionary *json, NSString *error) {
          self.busy = NO;
          BOOL valid = !error && [json[@"valid"] boolValue];
          completion(valid, error ?: (valid ? @"Hop le" : @"License chua kich hoat hoac da het han."));
      }];
}

- (void)activateTapped:(id)sender {
    (void)sender;
    if (self.busy) return;
    NSString *license = [self.licenseField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (license.length < 30) {
        [self updateStatus:@"Vui lòng nhập License Key hợp lệ."];
        return;
    }
    NSString *device = [self deviceID];
    if (!device.length) { [self updateStatus:@"Không thể lưu mã thiết bị trong Keychain."]; return; }

    self.busy = YES;
    [self setInputsEnabled:NO];
    [self updateStatus:@"Đang kích hoạt License..."];
    [self post:@"/keys/activate-with-key"
          data:@{@"key":license, @"device_id":device, @"label":@"iPhone"}
      completion:^(NSDictionary *result, NSString *error) {
          self.busy = NO;
          if (error || ![result[@"valid"] boolValue]) {
              [self setInputsEnabled:YES];
              [self updateStatus:error ?: @"License không hợp lệ."];
              return;
          }
          if (!KHWriteSecret(KHLicenseAccount, license)) {
              [self setInputsEnabled:YES];
              [self updateStatus:@"Không thể lưu License vào Keychain."];
              return;
          }
          [self updateStatus:@"Đã kích hoạt. Đang xác minh..."];
          [self verifyLicense:license completion:^(BOOL valid, NSString *message) {
              if (valid) [self unlock];
              else [self lockUIWithStatus:message ?: @"License không hợp lệ."];
          }];
      }];
}

@end

// Called when an injector actually loads this Mach-O dylib into the app process.
__attribute__((constructor)) static void KHGateEntry(void) {
    @autoreleasepool {
        [[KHGate shared] start];
    }
}
