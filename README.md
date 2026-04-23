If you have to change a function in the linux kernel and you want to see which subsystems do the functions, which call the function you want to change belong to, you simply have to run the following command on your terminal:
```
./trace.sh <function-you-want-to-trace> <kernel-directory>
```

Before running give the execute permissions:
```
chmod +x trace.sh
```
