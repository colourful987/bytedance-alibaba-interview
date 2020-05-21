//
//  main.m
//  lc125-0519
//
//  Created by pmst on 2020/5/19.
//  Copyright © 2020 pmst. All rights reserved.
//

#import <Foundation/Foundation.h>

char lowercase(char c){
    if(c>= 'A' && c<= 'Z'){
        return c - 'A' + 'a';
    } else{
        return c;
    }
}
bool isValid(char c){
    if(c >= '0' && c<='9')return true;
    
    if(c >= 'a' && c<='z')return true;
    
    if(c >= 'A' && c<='Z')return true;
    
    return false;
}
bool isPalindrome(char * s){
    int len = strlen(s);
    int i = 0;
    int j = len-1;

    while(i < j){
        while(i < len && isValid(s[i]) == false){
            i++;
        }
        while(j >= 0 && isValid(s[j]) == false){
            j--;
        }
        char c1 = lowercase(s[i++]);
        char c2 = lowercase(s[j--]);
        if(c1 != c2){
            return false;
        }
    }
    return true;
}

int main(int argc, const char * argv[]) {
    char str[100] = ".,";
    bool res = isPalindrome(str);
    return 0;
}
