/**
 * @name        DataCloudAuthService
 * @description Service class for authenticating with Salesforce CRM and Data Cloud using JWT and tenant token exchange.
 * @author      Debanjan Mukherjee
 * @created     20 Jun 2025
 */
public with sharing class DataCloudAuthService {

    /**
     * @description Container class for parsing token response.
     */
    public class TokenResponse {
        public String access_token;
        public String instance_url;
        public Map<String, Object> urls;
    }

    /**
     * @description Retrieves Data Cloud tenant token using CRM access token.
     */
    public static List<String> getDataCloudTenantToken(String crmHostAccessToken, String crmHostInstanceUrl, String dataspace) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        HttpResponse res;

        String tenantTokenUrl = crmHostInstanceUrl + getConfigValue('DataCloud_Token_Endpoint'); // e.g. '/services/a360/token'

        req.setEndpoint(tenantTokenUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body = 'grant_type=' + getConfigValue('Grant_Type_CDP') +
                      '&subject_token=' + EncodingUtil.urlEncode(crmHostAccessToken, 'UTF-8') +
                      '&subject_token_type=' + getConfigValue('Subject_Token_Type');

        if (String.isNotBlank(dataspace)) {
            body += '&dataspace=' + dataspace;
        }

        req.setBody(body);
        res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CalloutException('Data Cloud token exchange failed: ' + res.getBody());
        }

        TokenResponse tokenResponse = (TokenResponse) JSON.deserialize(res.getBody(), TokenResponse.class);
        List<String> tokens = new List<String>{
            'https://' + tokenResponse.instance_url,
            'Bearer ' + tokenResponse.access_token
        };
        return tokens;
    }

    /**
     * @description Authenticates with Salesforce CRM using JWT and retrieves Data Cloud token.
     */
    public static List<String> authenticateWithDataCloud() {
        String jwt = generateJwt();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(getConfigValue('CRM_JWT_Endpoint')); // e.g. 'https://login.salesforce.com/services/oauth2/token'
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=' + getConfigValue('JWT_Grant_Type') + '&assertion=' + EncodingUtil.urlEncode(jwt, 'UTF-8'));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CalloutException('JWT token generation failed: ' + res.getBody());
        }

        TokenResponse token = (TokenResponse) JSON.deserialize(res.getBody(), TokenResponse.class);
        return getDataCloudTenantToken(token.access_token, token.instance_url, '');
    }
    /**
     * @description Authenticates with Salesforce CRM using JWT and retrieves Data Cloud token.
     */
    public static TokenResponse authOnlyCRM() {
        String jwt = generateJwt();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(getConfigValue('CRM_JWT_Endpoint')); // e.g. 'https://login.salesforce.com/services/oauth2/token'
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=' + getConfigValue('JWT_Grant_Type') + '&assertion=' + EncodingUtil.urlEncode(jwt, 'UTF-8'));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new CalloutException('JWT token generation failed: ' + res.getBody());
        }

        TokenResponse token = (TokenResponse) JSON.deserialize(res.getBody(), TokenResponse.class);
        return token;
    }

    /**
     * @description Generates a signed JWT using certificate and values from CMDT.
     */
    private static String generateJwt() {
        Long now = DateTime.now().getTime() / 1000;
        Long exp = now + 300;

        Map<String, Object> header = new Map<String, Object>{
            'alg' => 'RS256',
            'typ' => 'JWT'
        };

        Map<String, Object> claims = new Map<String, Object>{
            'iss' => getConfigValue('Consumer_Key'),
            'sub' => getConfigValue('JWT_Username'),
            'aud' => getConfigValue('JWT_Audience'),
            'exp' => exp
        };

        String encodedHeader = base64UrlSafe(JSON.serialize(header));
        String encodedClaims = base64UrlSafe(JSON.serialize(claims));
        String token = encodedHeader + '.' + encodedClaims;

        Blob signature = Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(token), getConfigValue('Certificate_Name'));
        String encodedSignature = base64UrlSafe(signature);

        return token + '.' + encodedSignature;
    }

    /**
     * @description Encodes input to Base64 URL-safe format.
     */
    private static String base64UrlSafe(String input) {
        return EncodingUtil.base64Encode(Blob.valueOf(input))
            .replace('+', '-')
            .replace('/', '_')
            .replaceAll('=+$', '');
    }

    private static String base64UrlSafe(Blob input) {
        return EncodingUtil.base64Encode(input)
            .replace('+', '-')
            .replace('/', '_')
            .replaceAll('=+$', '');
    }

    /**
     * @description Fetches configuration values from Generic_Key_Value__mdt.
     */
    private static String getConfigValue(String keyName) {
        Generic_Key_Value__mdt config = [
            SELECT Value__c FROM Generic_Key_Value__mdt WHERE Key__c = :keyName LIMIT 1
        ];
        return config != null ? config.Value__c : '';
    }
}