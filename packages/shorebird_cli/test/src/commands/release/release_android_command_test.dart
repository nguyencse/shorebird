import 'dart:io' hide Platform;

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/os/operating_system_interface.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../fakes.dart';
import '../../mocks.dart';

void main() {
  group(ReleaseAndroidCommand, () {
    const appId = 'test-app-id';
    const shorebirdYaml = ShorebirdYaml(appId: appId);
    const flutterRevision = '83305b5088e6fe327fb3334a73ff190828d85713';
    const flutterVersionAndRevision = '3.10.6 (83305b5088)';
    const versionName = '1.2.3';
    const versionCode = '1';
    const version = '$versionName+$versionCode';
    const appDisplayName = 'Test App';
    const arch = 'aarch64';
    const releasePlatform = ReleasePlatform.android;
    final appMetadata = AppMetadata(
      appId: appId,
      displayName: appDisplayName,
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );
    final release = Release(
      id: 0,
      appId: appId,
      version: version,
      flutterRevision: flutterRevision,
      displayName: '1.2.3+1',
      platformStatuses: {},
      createdAt: DateTime(2023),
      updatedAt: DateTime(2023),
    );

    const javaHome = 'test-java-home';

    late ArgResults argResults;
    late Bundletool bundletool;
    late http.Client httpClient;
    late CodePushClientWrapper codePushClientWrapper;
    late Directory shorebirdRoot;
    late Directory projectRoot;
    late Doctor doctor;
    late Platform platform;
    late Auth auth;
    late Cache cache;
    late Java java;
    late Logger logger;
    late OperatingSystemInterface operatingSystemInterface;
    late Progress progress;
    late ShorebirdProcessResult flutterBuildProcessResult;
    late ShorebirdProcessResult flutterPubGetProcessResult;
    late ShorebirdFlutterValidator flutterValidator;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdValidator shorebirdValidator;
    late ReleaseAndroidCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          authRef.overrideWith(() => auth),
          bundletoolRef.overrideWith(() => bundletool),
          cacheRef.overrideWith(() => cache),
          codePushClientWrapperRef.overrideWith(() => codePushClientWrapper),
          doctorRef.overrideWith(() => doctor),
          engineConfigRef.overrideWith(() => const EngineConfig.empty()),
          javaRef.overrideWith(() => java),
          loggerRef.overrideWith(() => logger),
          osInterfaceRef.overrideWith(() => operatingSystemInterface),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(ReleasePlatform.android);
      registerFallbackValue(ReleaseStatus.draft);
      registerFallbackValue(FakeRelease());
      registerFallbackValue(FakeShorebirdProcess());
    });

    setUp(() {
      argResults = MockArgResults();
      bundletool = MockBundleTool();
      codePushClientWrapper = MockCodePushClientWrapper();
      doctor = MockDoctor();
      httpClient = MockHttpClient();
      operatingSystemInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      shorebirdRoot = Directory.systemTemp.createTempSync();
      projectRoot = Directory.systemTemp.createTempSync();
      auth = MockAuth();
      cache = MockCache();
      java = MockJava();
      progress = MockProgress();
      logger = MockLogger();
      flutterBuildProcessResult = MockProcessResult();
      flutterPubGetProcessResult = MockProcessResult();
      flutterValidator = MockShorebirdFlutterValidator();
      shorebirdProcess = MockShorebirdProcess();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdValidator = MockShorebirdValidator();

      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(shorebirdRoot);
      when(
        () => shorebirdEnv.getShorebirdProjectRoot(),
      ).thenReturn(projectRoot);
      when(() => shorebirdEnv.flutterRevision).thenReturn(flutterRevision);
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(false);

      when(
        () => shorebirdFlutter.getVersionAndRevision(),
      ).thenAnswer((_) async => flutterVersionAndRevision);

      when(
        () => shorebirdProcess.run(
          'flutter',
          ['--no-version-check', 'pub', 'get', '--offline'],
          runInShell: any(named: 'runInShell'),
          useVendedFlutter: false,
        ),
      ).thenAnswer((_) async => flutterPubGetProcessResult);
      when(
        () => shorebirdProcess.run(
          'flutter',
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => flutterBuildProcessResult);

      when(() => argResults.rest).thenReturn([]);
      when(() => argResults['arch']).thenReturn(arch);
      when(() => argResults['platform']).thenReturn(releasePlatform);
      when(() => argResults['artifact']).thenReturn('aab');
      when(() => auth.isAuthenticated).thenReturn(true);
      when(() => auth.client).thenReturn(httpClient);
      when(() => cache.updateAll()).thenAnswer((_) async => {});
      when(
        () => cache.getArtifactDirectory(any()),
      ).thenReturn(Directory.systemTemp.createTempSync());
      when(() => logger.progress(any())).thenReturn(progress);
      when(() => logger.confirm(any())).thenReturn(true);
      when(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      ).thenReturn(version);
      when(
        () => flutterBuildProcessResult.exitCode,
      ).thenReturn(ExitCode.success.code);
      when(() => flutterPubGetProcessResult.exitCode)
          .thenReturn(ExitCode.success.code);
      when(
        () => codePushClientWrapper.getApp(appId: any(named: 'appId')),
      ).thenAnswer((_) async => appMetadata);
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => codePushClientWrapper.ensureReleaseIsNotActive(
          release: any(named: 'release'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      ).thenAnswer((_) async => release);
      when(
        () => codePushClientWrapper.createAndroidReleaseArtifacts(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          projectRoot: any(named: 'projectRoot'),
          aabPath: any(named: 'aabPath'),
          platform: any(named: 'platform'),
          architectures: any(named: 'architectures'),
          flavor: any(named: 'flavor'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async {});
      when(() => doctor.androidCommandValidators)
          .thenReturn([flutterValidator]);
      when(flutterValidator.validate).thenAnswer((_) async => []);
      when(() => java.home).thenReturn(javaHome);
      when(
        () => bundletool.getVersionName(any()),
      ).thenAnswer((_) async => versionName);
      when(
        () => bundletool.getVersionCode(any()),
      ).thenAnswer((_) async => versionCode);
      when(() => operatingSystemInterface.which('flutter'))
          .thenReturn('/path/to/flutter');
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
          supportedOperatingSystems: any(named: 'supportedOperatingSystems'),
        ),
      ).thenAnswer((_) async {});

      command = runWithOverrides(ReleaseAndroidCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
          validators: any(named: 'validators'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
          validators: [flutterValidator],
        ),
      ).called(1);
    });

    test('exits with code unavailable when --split-per-abi is provided',
        () async {
      when(() => argResults['artifact']).thenReturn('apk');
      when(() => argResults['split-per-abi']).thenReturn(true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, ExitCode.unavailable.code);
    });

    test('exits with code 70 when building fails', () async {
      when(() => flutterBuildProcessResult.exitCode).thenReturn(1);
      when(() => flutterBuildProcessResult.stderr).thenReturn('oops');
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, equals(ExitCode.software.code));
    });

    test('errors when detecting release version name fails', () async {
      final exception = Exception(
        'Failed to extract version name from app bundle: oops',
      );
      when(() => bundletool.getVersionName(any())).thenThrow(exception);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('errors when detecting release version code fails', () async {
      final exception = Exception(
        'Failed to extract version code from app bundle: oops',
      );
      when(() => bundletool.getVersionCode(any())).thenThrow(exception);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.software.code);
      verify(() => progress.fail('$exception')).called(1);
    });

    test('aborts when user opts out', () async {
      when(() => logger.confirm(any())).thenReturn(false);
      when(
        () => logger.prompt(
          'What is the version of this release?',
          defaultValue: any(named: 'defaultValue'),
        ),
      ).thenAnswer((_) => '1.0.0');
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verify(() => logger.info('Aborting.')).called(1);
      verifyNever(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: any(named: 'appId'),
          releaseId: any(named: 'releaseId'),
          platform: any(named: 'platform'),
          status: any(named: 'status'),
        ),
      );
    });

    test(
        'does not prompt for confirmation '
        'when --release-version and --force are used', () async {
      when(() => argResults['force']).thenReturn(true);
      when(() => argResults['release-version']).thenReturn(version);
      final exitCode = await runWithOverrides(command.run);
      verify(
        () => logger.success('\n✅ Published Release $version!'),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => logger.prompt(any(), defaultValue: any(named: 'defaultValue')),
      );
    });

    test('succeeds when release is successful', () async {
      final exitCode = await runWithOverrides(command.run);
      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      final aabPath = p.join(
        projectRoot.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'app-release.aab',
      );
      // Verify info message does not include apk instructions.
      verify(
        () => logger.info('''

Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(aabPath)}

For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
'''),
      ).called(1);
      verify(
        () => codePushClientWrapper.createAndroidReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          projectRoot: any(named: 'projectRoot'),
          aabPath: any(named: 'aabPath'),
          architectures: any(named: 'architectures'),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('succeeds when release is successful (with apk)', () async {
      when(() => argResults['artifact']).thenReturn('apk');
      final exitCode = await runWithOverrides(command.run);
      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      // Verify info message does include apk instructions.
      final aabPath = p.join(
        projectRoot.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'app-release.aab',
      );
      final apkPath = p.join(
        projectRoot.path,
        'build',
        'app',
        'outputs',
        'apk',
        'release',
        'app-release.apk',
      );
      verify(
        () => logger.info('''

Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(aabPath)}

Or distribute the apk:
${lightCyan.wrap(apkPath)}

For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
'''),
      ).called(1);
      verify(
        () => codePushClientWrapper.createAndroidReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          projectRoot: any(named: 'projectRoot'),
          aabPath: any(named: 'aabPath'),
          architectures: any(named: 'architectures'),
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
        ),
      ).called(1);
      const buildApkArguments = ['build', 'apk', '--release'];
      verify(
        () => shorebirdProcess.run(
          'flutter',
          buildApkArguments,
          runInShell: true,
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    group('after a build', () {
      group('when the build is successful', () {
        setUp(() {
          when(() => flutterBuildProcessResult.exitCode)
              .thenReturn(ExitCode.success.code);
        });

        group('when flutter is installed', () {
          setUp(() {
            when(() => operatingSystemInterface.which('flutter'))
                .thenReturn('/path/to/flutter');
          });

          test('runs flutter pub get with system flutter', () async {
            await runWithOverrides(command.run);

            verify(
              () => shorebirdProcess.run(
                'flutter',
                ['--no-version-check', 'pub', 'get', '--offline'],
                runInShell: any(named: 'runInShell'),
                useVendedFlutter: false,
              ),
            ).called(1);
          });
        });

        group('when flutter is not installed', () {
          setUp(() {
            when(() => operatingSystemInterface.which('flutter'))
                .thenReturn(null);
          });

          test('does not attempt to run flutter pub get', () async {
            await runWithOverrides(command.run);

            verifyNever(
              () => shorebirdProcess.run(
                'flutter',
                ['--no-version-check', 'pub', 'get', '--offline'],
                runInShell: any(named: 'runInShell'),
                useVendedFlutter: false,
              ),
            );
          });
        });
      });

      group('when the build fails', () {
        setUp(() {
          when(() => flutterBuildProcessResult.exitCode)
              .thenReturn(ExitCode.software.code);
        });

        group('when flutter is installed', () {
          setUp(() {
            when(() => operatingSystemInterface.which('flutter'))
                .thenReturn('/path/to/flutter');
          });

          test('runs flutter pub get with system flutter', () async {
            await runWithOverrides(command.run);

            verify(
              () => shorebirdProcess.run(
                'flutter',
                ['--no-version-check', 'pub', 'get', '--offline'],
                runInShell: any(named: 'runInShell'),
                useVendedFlutter: false,
              ),
            ).called(1);
          });

          test('prints error message if system flutter pub get fails',
              () async {
            when(() => flutterPubGetProcessResult.exitCode).thenReturn(1);

            await runWithOverrides(command.run);

            verify(
              () => logger.warn(
                '''
Build was successful, but `flutter pub get` failed to run after the build completed. You may see unexpected behavior in VS Code.

Either run `flutter pub get` manually, or follow the steps in ${link(uri: Uri.parse('https://docs.shorebird.dev/troubleshooting#i-installed-shorebird-and-now-i-cant-run-my-app-in-vs-code'))}.
''',
              ),
            ).called(1);
          });
        });

        group('when flutter is not installed', () {
          setUp(() {
            when(() => operatingSystemInterface.which('flutter'))
                .thenReturn(null);
          });

          test('does not attempt to run flutter pub get', () async {
            await runWithOverrides(command.run);

            verifyNever(
              () => shorebirdProcess.run(
                'flutter',
                ['--no-version-check', 'pub', 'get', '--offline'],
                runInShell: any(named: 'runInShell'),
                useVendedFlutter: false,
              ),
            );
          });
        });
      });
    });

    test(
        'succeeds when release is successful '
        'with flavors and target', () async {
      const flavor = 'development';
      final target = p.join('lib', 'main_development.dart');
      when(() => argResults['flavor']).thenReturn(flavor);
      when(() => argResults['target']).thenReturn(target);
      const shorebirdYaml = ShorebirdYaml(
        appId: 'productionAppId',
        flavors: {flavor: appId},
      );
      when(() => shorebirdEnv.getShorebirdYaml()).thenReturn(shorebirdYaml);
      final exitCode = await runWithOverrides(command.run);

      verify(() => logger.success('\n✅ Published Release $version!')).called(1);
      verify(
        () => codePushClientWrapper.createAndroidReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          projectRoot: any(named: 'projectRoot'),
          aabPath: any(named: 'aabPath'),
          architectures: any(named: 'architectures'),
          flavor: flavor,
        ),
      ).called(1);
      verify(
        () => codePushClientWrapper.updateReleaseStatus(
          appId: appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
        ),
      ).called(1);
      expect(exitCode, ExitCode.success.code);
    });

    test('does not create new release if existing release is present',
        () async {
      when(
        () => codePushClientWrapper.maybeGetRelease(
          appId: any(named: 'appId'),
          releaseVersion: any(named: 'releaseVersion'),
        ),
      ).thenAnswer((_) async => release);
      final exitCode = await runWithOverrides(command.run);
      expect(exitCode, ExitCode.success.code);
      verifyNever(
        () => codePushClientWrapper.createRelease(
          appId: any(named: 'appId'),
          version: any(named: 'version'),
          flutterRevision: any(named: 'flutterRevision'),
          platform: any(named: 'platform'),
        ),
      );
    });

    test('does not prompt if running on CI', () async {
      when(() => shorebirdEnv.isRunningOnCI).thenReturn(true);

      final exitCode = await runWithOverrides(command.run);

      expect(exitCode, equals(ExitCode.success.code));
      verifyNever(() => logger.confirm(any()));
    });
  });
}
