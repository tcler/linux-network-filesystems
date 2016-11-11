# linux-network-filesystems

record/introduce {export options} {mount options} funtions features of NFS

## Common Offers by NFSv3 and NFSv4:

| Category      | Options                                | Status            |
|:------------- |:-------------------------------------- |:----------------- |
| performance   | sync/async/ac/wdelay                   | taken             |
| crossmount    | crossmnt/nohide/no\_subtree\_check     | taken             |
| permissions   | (all/no_root/root)\_squash/ro/anonuid  |                   |
| security      | sec=flavors...                         |                   |
| network       | proto/timeo...                         |                   |
TBD: Full features record is at [features-list-of-network-filesystems](https://docs.google.com/a/redhat.com/spreadsheets/d/1O11eMvHPEy7Vr8xMuAPV5_6CKToClyF2wELulo7pddg/edit?usp=sharing)

## Special Offers by NFSv4.1 and NFSv4.2:

| Category      | Options                                | Status            |
|:------------- |:-------------------------------------- |:----------------- |
| pNFS          |                                        |                   |
| TBD           |                                        |                   |
TBD: Full features record is also at [features-list-of-network-filesystems](https://docs.google.com/a/redhat.com/spreadsheets/d/1O11eMvHPEy7Vr8xMuAPV5_6CKToClyF2wELulo7pddg/edit?usp=sharing)

## Special Offers by NetApp and Windows:

| Category      | Options                                | Status            |
|:------------- |:-------------------------------------- |:----------------- |
| delegation    |                                        |                   |
| TBD           |                                        |                   |

## Misc:

| Case                                   | Description                       |
|:-------------------------------------- |:--------------------------------- |
| nmap\_detect\_nfs\_ver                 | How nmap detects NFS version      |
| TBD                                    |                                   |