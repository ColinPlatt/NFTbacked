<?php

use App\Http\Controllers\CovalentController;
use App\Models\NFTData;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| is assigned the "api" middleware group. Enjoy building your API!
|
*/


Route::get('apitest',[CovalentController::class,'index']);

Route::get('latest-price',function (){
    $priceData = NFTData::orderByDesc('created_at')->first();
    return $priceData;
});
