//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class ConfigAdminApi {
  ConfigAdminApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Get the admin configuration
  ///
  /// Retrieve admin configuration.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getAdminConfigWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final apiPath = r'/admin/config';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      apiPath,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Get the admin configuration
  ///
  /// Retrieve admin configuration.
  Future<AdminConfigDto?> getAdminConfig({ Future<void>? abortTrigger, }) async {
    final response = await getAdminConfigWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AdminConfigDto',) as AdminConfigDto;
    
    }
    return null;
  }

  /// Get the system configuration defaults
  ///
  /// Retrieve the default value of every system configuration property.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getAdminConfigDefaultsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final apiPath = r'/admin/config/defaults';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      apiPath,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Get the system configuration defaults
  ///
  /// Retrieve the default value of every system configuration property.
  Future<AdminConfigDto?> getAdminConfigDefaults({ Future<void>? abortTrigger, }) async {
    final response = await getAdminConfigDefaultsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AdminConfigDto',) as AdminConfigDto;
    
    }
    return null;
  }

  /// Get storage template options
  ///
  /// Retrieve the storage template variables and the preset templates, each with an example path.
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> getAdminStorageTemplateOptionsWithHttpInfo({ Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final apiPath = r'/admin/config/storage-template';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      apiPath,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Get storage template options
  ///
  /// Retrieve the storage template variables and the preset templates, each with an example path.
  Future<StorageTemplateOptionsResponseDto?> getAdminStorageTemplateOptions({ Future<void>? abortTrigger, }) async {
    final response = await getAdminStorageTemplateOptionsWithHttpInfo(abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'StorageTemplateOptionsResponseDto',) as StorageTemplateOptionsResponseDto;
    
    }
    return null;
  }

  /// Preview a storage template
  ///
  /// Render an example path from the provided storage template.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [StorageTemplatePreviewDto] storageTemplatePreviewDto (required):
  Future<Response> previewStorageTemplateWithHttpInfo(StorageTemplatePreviewDto storageTemplatePreviewDto, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final apiPath = r'/admin/config/storage-template/preview';

    // ignore: prefer_final_locals
    Object? postBody = storageTemplatePreviewDto;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      apiPath,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Preview a storage template
  ///
  /// Render an example path from the provided storage template.
  ///
  /// Parameters:
  ///
  /// * [StorageTemplatePreviewDto] storageTemplatePreviewDto (required):
  Future<StorageTemplatePreviewResponseDto?> previewStorageTemplate(StorageTemplatePreviewDto storageTemplatePreviewDto, { Future<void>? abortTrigger, }) async {
    final response = await previewStorageTemplateWithHttpInfo(storageTemplatePreviewDto, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'StorageTemplatePreviewResponseDto',) as StorageTemplatePreviewResponseDto;
    
    }
    return null;
  }

  /// Update the system configuration
  ///
  /// Update the system configuration with a new system configuration.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [AdminConfigDto] adminConfigDto (required):
  Future<Response> updateAdminConfigWithHttpInfo(AdminConfigDto adminConfigDto, { Future<void>? abortTrigger, }) async {
    // ignore: prefer_const_declarations
    final apiPath = r'/admin/config';

    // ignore: prefer_final_locals
    Object? postBody = adminConfigDto;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      apiPath,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
      abortTrigger: abortTrigger,
    );
  }

  /// Update the system configuration
  ///
  /// Update the system configuration with a new system configuration.
  ///
  /// Parameters:
  ///
  /// * [AdminConfigDto] adminConfigDto (required):
  Future<AdminConfigDto?> updateAdminConfig(AdminConfigDto adminConfigDto, { Future<void>? abortTrigger, }) async {
    final response = await updateAdminConfigWithHttpInfo(adminConfigDto, abortTrigger: abortTrigger,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'AdminConfigDto',) as AdminConfigDto;
    
    }
    return null;
  }
}
