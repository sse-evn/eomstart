// //// test/services/map_data_loader_test.dart

// import 'dart:io';
// import 'dart:convert';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:http/http.dart' as http;
// import 'package:mocktail/mocktail.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:test/test.dart';
// import 'package:micro_mobility_app/services/map_load/map_data_loader.dart';

// // Моки
// class MockHttpClient extends Mock implements http.Client {}

// class MockResponse extends Mock implements http.Response {}

// class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// class MockDirectory extends Mock implements Directory {}

// class MockFile extends Mock implements File {}

// // Для мока path_provider
// class MockPathProvider extends Mock {
//   Future<Directory> getApplicationDocumentsDirectory() =>
//       Future.value(MockDirectory());
// }

// // Глобальная функция для замены реальной
// Directory Function() GetApplicationDocumentsDirectory = () => throw UnimplementedError();

// void main() {
//   late MapDataLoader mapDataLoader;
//   late MockHttpClient mockHttpClient;
//   late MockFlutterSecureStorage mockStorage;
//   late MockFile mockFile;
//   late MockDirectory mockDirectory;
//   late MockPathProvider mockPathProvider;

//   const testMapId = 1;
//   const testFileName = 'test_map.geojson';
//   final testToken = 'fake-jwt-token';
//   final testGeoJson = '{"type": "FeatureCollection", "features": []}';

//   setUpAll(() {
//     registerFallbackValue(Uri());
//   });

//   setUp(() {
//     mockHttpClient = MockHttpClient();
//     mockStorage = MockFlutterSecureStorage();
//     mockFile = MockFile();
//     mockDirectory = MockDirectory();
//     mockPathProvider = MockPathProvider();

//     // Мокаем path_provider
//     when(() => mockPathProvider.getApplicationDocumentsDirectory())
//         .thenAnswer((_) async => mockDirectory);

//     when(() => mockDirectory.path).thenReturn('/fake/path');
//     when(() => mockDirectory.create(recursive: true))
//         .thenAnswer((_) async => mockDirectory);

//     // Устанавливаем мок для global function
//     GetApplicationDocumentsDirectory = () => mockPathProvider.getApplicationDocumentsDirectory();

//     // Мокаем файл
//     when(() => mockFile.path).thenReturn('/fake/path/map_1.geojson');
//     when(() => mockFile.existsSync()).thenAnswer((_) => false);
//     when(() => mockFile.writeAsString(any())).thenAnswer((_) async => mockFile);
//     when(() => mockFile.readAsString()).thenAnswer((_) async => testGeoJson);

//     // Мокаем storage
//     when(() => mockStorage.read(key: 'jwt_token'))
//         .thenAnswer((_) async => testToken);

//     // Мокаем HTTP
//     when(() => mockHttpClient.get(any())).thenAnswer((_) async {
//       final response = MockResponse();
//       when(() => response.statusCode).thenReturn(200);
//       when(() => response.body).thenReturn('');
//       return response;
//     });
//   });

//   tearDown(() {
//     reset(mockHttpClient);
//     reset(mockStorage);
//     reset(mockFile);
//     reset(mockDirectory);
//   });

//   group('MapDataLoader', () {
//     setUp(() {
//       mapDataLoader = MapDataLoader(
//         httpClient: mockHttpClient,
//         secureStorage: mockStorage,
//       );
//     });

//     group('loadAvailableMaps', () {
//       test('должен вернуть список карт при успешном ответе', () async {
//         // Arrange
//         final responseBody = jsonEncode([
//           {'id': 1, 'city': 'Москва', 'description': 'Центр'},
//           {'id': 2, 'city': 'СПб', 'description': 'Юг'},
//         ]);

//         when(() => mockHttpClient.get(any())).thenAnswer((_) async {
//           final response = MockResponse();
//           when(() => response.statusCode).thenReturn(200);
//           when(() => response.body).thenReturn(responseBody);
//           return response;
//         });

//         // Act
//         final result = await mapDataLoader.loadAvailableMaps();

//         // Assert
//         expect(result, isList);
//         expect(result.length, 2);
//         expect(result[0]['city'], 'Москва');
//       });

//       test('должен выбросить исключение, если токен отсутствует', () async {
//         // Arrange
//         when(() => mockStorage.read(key: 'jwt_token')).thenAnswer((_) async => null);

//         // Act & Assert
//         expect(mapDataLoader.loadAvailableMaps(), throwsException);
//       });

//       test('должен выбросить исключение при ошибке сети', () async {
//         // Arrange
//         when(() => mockHttpClient.get(any())).thenThrow(Exception('Network error'));

//         // Act & Assert
//         expect(mapDataLoader.loadAvailableMaps(), throwsException);
//       });
//     });

//     group('loadGeoJsonForMap', () {
//       test('должен загрузить GeoJSON с сервера и сохранить локально', () async {
//         // Arrange
//         final metadataResponse = jsonEncode({
//           'id': 1,
//           'file_name': testFileName,
//         });

//         final fileResponse = MockResponse();
//         when(() => fileResponse.statusCode).thenReturn(200);
//         when(() => fileResponse.body).thenReturn(testGeoJson);

//         // Метаданные карты
//         when(() => mockHttpClient.get(any())).thenAnswer((_) async {
//           final response = MockResponse();
//           when(() => response.statusCode).thenReturn(200);
//           when(() => response.body).thenReturn(metadataResponse);
//           return response;
//         });

//         // Сам GeoJSON файл
//         when(() => mockHttpClient.get(any())).thenAnswer((_) async => fileResponse);

//         // Мокаем child для Directory
//         when(() => mockDirectory.child(any())).thenReturn(mockFile);

//         // Act
//         final result = await mapDataLoader.loadGeoJsonForMap(testMapId);

//         // Assert
//         expect(result, testGeoJson);
//         verify(() => mockFile.writeAsString(testGeoJson)).called(1);
//       });

//       test('должен использовать локальный файл, если он существует', () async {
//         // Arrange
//         when(() => mockDirectory.child(any())).thenReturn(mockFile);
//         when(() => mockFile.existsSync()).thenReturn(true);
//         when(() => mockFile.readAsString()).thenAnswer((_) async => testGeoJson);

//         // Act
//         final result = await mapDataLoader.loadGeoJsonForMap(testMapId);

//         // Assert
//         expect(result, testGeoJson);
//         verifyNever(() => mockHttpClient.get(any()));
//       });

//       test('должен использовать локальный файл при ошибке сети', () async {
//         // Arrange
//         when(() => mockDirectory.child(any())).thenReturn(mockFile);
//         when(() => mockFile.existsSync()).thenReturn(true);
//         when(() => mockFile.readAsString()).thenAnswer((_) async => testGeoJson);

//         when(() => mockHttpClient.get(any())).thenThrow(Exception('Network error'));

//         // Act
//         final result = await mapDataLoader.loadGeoJsonForMap(testMapId);

//         // Assert
//         expect(result, testGeoJson);
//       });

//       test('должен выбросить исключение, если нет ни сервера, ни кэша', () async {
//         // Arrange
//         when(() => mockDirectory.child(any())).thenReturn(mockFile);
//         when(() => mockFile.existsSync()).thenReturn(false);
//         when(() => mockHttpClient.get(any())).thenThrow(Exception('Network error'));

//         // Act & Assert
//         expect(mapDataLoader.loadGeoJsonForMap(testMapId), throwsException);
//       });
//     });

//     group('downloadMapLocally', () {
//       test('должен успешно загрузить и сохранить карту локально', () async {
//         // Arrange
//         final metadataResponse = jsonEncode({
//           'id': 1,
//           'file_name': testFileName,
//         });

//         final fileResponse = MockResponse();
//         when(() => fileResponse.statusCode).thenReturn(200);
//         when(() => fileResponse.body).thenReturn(testGeoJson);

//         when(() => mockHttpClient.get(any())).thenAnswer((_) async {
//           final response = MockResponse();
//           when(() => response.statusCode).thenReturn(200);
//           when(() => response.body).thenReturn(metadataResponse);
//           return response;
//         });

//         when(() => mockHttpClient.get(any())).thenAnswer((_) async => fileResponse);

//         when(() => mockDirectory.child(any())).thenReturn(mockFile);
//         when(() => mockFile.writeAsString(any())).thenAnswer((_) async => mockFile);

//         // Act
//         await mapDataLoader.downloadMapLocally(testMapId);

//         // Assert
//         verify(() => mockFile.writeAsString(testGeoJson)).called(1);
//       });

//       test('не должен падать при ошибке загрузки', () async {
//         // Arrange
//         when(() => mockHttpClient.get(any())).thenThrow(Exception('Download failed'));

//         // Act & Assert
//         expect(() => mapDataLoader.downloadMapLocally(testMapId), returnsNormally);
//       });
//     });
//   });
// }
