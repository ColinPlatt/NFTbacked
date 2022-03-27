<?php

namespace App\Models;


use Illuminate\Database\Eloquent\Model;

class NFTData extends Model
{
    protected $table = 'nft_data';

    protected $fillable = [
        'name',
        'address',
        'price',
    ];

}
