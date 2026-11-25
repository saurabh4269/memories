# openapi.model.PersonUsersResponseDtoInner

## Load the model package
```dart
import 'package:openapi/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**personId** | **String** | Person ID | 
**role** | [**PersonUserRole**](PersonUserRole.md) | Access role | 
**sharedBy** | [**UserResponseDto**](UserResponseDto.md) | The user that gave access to this person | 
**sharedById** | **String** | User ID of the user that gave access to this person | 
**sharedWith** | [**UserResponseDto**](UserResponseDto.md) | The user that was given access to this person | 
**sharedWithId** | **String** | User ID of the user that was given access to this person | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


