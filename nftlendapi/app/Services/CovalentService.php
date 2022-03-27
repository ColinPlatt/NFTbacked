<?php

namespace App\Services;

use App\Models\NFTData;
use Carbon\Carbon;

class CovalentService{

    const baseURL = 'https://api.covalenthq.com/v1/43114/nft_market/collection';
    private $collectionAddress;

    public function __construct($collectionAddress = '0x4245a1bd84eb5f3ebc115c2edf57e50667f98b0b'){
        $this->collectionAddress = $collectionAddress;
    }

    public function fetchCollectionData($from = null, $to = null)
    {
        if(empty($from) || empty($to)){
            $from = Carbon::now()->subDays(2)->format('Y-m-d');
            $to = Carbon::now()->format('Y-m-d');
        }
        $url = self::baseURL.'/'.$this->collectionAddress.'/';
        $params = [
            'format' => 'JSON',
            'quote-currency' => 'USD',
            'key' => env('COVALENT_KEY'),
            'from' => $from,
            'to' => $to,
        ];

        $client = new \GuzzleHttp\Client();
        $response = $client->request('GET', $url,['query' => $params]);
        $statusCode = $response->getStatusCode();

        if($statusCode == 200){
            $responseBody = json_decode($response->getBody(), true);
        }

        return $responseBody['data'];


    }

    public function getCollectionAveragePrice($data)
    {
        // extract avg price, in USD
        $floorPrice = $data['items'][0]['floor_price_quote_7d'];
        return $floorPrice;

    }

    public function updateCollectionAveragePrice($price)
    {
        NFTData::create([
            'name' => env('COLLECTION_NAME','Hoppers') ,
            'address' => env('COLLECTION_ADDRESS','0x4245a1bd84eb5f3ebc115c2edf57e50667f98b0b'),
            'price' => $price,
        ]);
    }

}
