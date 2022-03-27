<?php

namespace App\Console\Commands;

use App\Services\CovalentService;
use Carbon\Carbon;
use Illuminate\Console\Command;

class FetchPriceData extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'fetch-prices';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Fetch price data for NFT collection';

    /**
     * Execute the console command.
     *
     * @return int
     */
    public function handle()
    {
        $service = new CovalentService();
        $response = $service->fetchCollectionData();
        $price = $service->getCollectionAveragePrice($response);
        $service->updateCollectionAveragePrice($price);
    }
}
