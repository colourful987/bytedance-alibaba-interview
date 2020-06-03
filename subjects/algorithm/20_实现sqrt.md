# 实现 sqrt

二分法：

```c
#define Epsilon 0.0000001

double mySqrt(int x){
    if(x == 0)return x;
  
    double l = Epsilon;
    double r = x;

    while(l + Epsilon < r){
        double mid = (r-l)/2.f + l;
        if(mid * mid > x){
            r = mid ;
        } else {
            l = mid+Epsilon;
        }
    }
    return l;
}
```

牛顿法：

```c
double mySqrt2(int x){
    if(x == 0)return x;
      double c = x;
      double x0 = x;
      
    while(1){
      double xi = 0.5 *(x0 + c/x0);
      if(ABS(x0-xi) < 1e-6)break;
      x0 = xi;
    }
    
    return x0;
}
```

