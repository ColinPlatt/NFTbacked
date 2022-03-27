<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\Http;
use Illuminate\Routing\Controller as BaseController;

class CovalentController extends BaseController
{
    public function index()
    {
        $baseURL = 'https://api.covalenthq.com/v1/43114/nft_market/collection/0x4245a1bd84eb5f3ebc115c2edf57e50667f98b0b/?quote-currency=USD&format=JSON&from=2022-03-01&to=2022-03-31&key=ckey_c1b83992f3bc44379dbf9f2684a';
        $apiURL = $baseURL;
        $client = new \GuzzleHttp\Client();
        $response = $client->request('GET', $apiURL);

        $statusCode = $response->getStatusCode();
        $responseBody = json_decode($response->getBody(), true);

        dd($responseBody['data']['items'][0]);
    }
}
