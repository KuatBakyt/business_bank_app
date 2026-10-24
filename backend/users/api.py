import logging
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from drf_spectacular.utils import extend_schema
from rest_framework import generics, serializers, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken, TokenError
from rest_framework.views import APIView
from config.throttling import LoginThrottle
from banking.serializers import RegisterSerializer, UserSerializer


class RegisterView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    throttle_classes = [LoginThrottle]
    serializer_class = RegisterSerializer

    @extend_schema(responses={201: UserSerializer})
    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            with transaction.atomic():
                user = get_user_model().objects.create_user(**serializer.validated_data)
        except IntegrityError:
            raise ValidationError({"email": "Email уже зарегистрирован"}) from None
        return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


class EmailTokenSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        attrs["email"] = attrs["email"].strip().lower()
        try:
            return super().validate(attrs)
        except Exception:
            logging.getLogger("security").warning("login_failed")
            raise


class LoginView(TokenObtainPairView):
    serializer_class = EmailTokenSerializer
    throttle_classes = [LoginThrottle]


class RefreshView(TokenRefreshView):
    throttle_classes = [LoginThrottle]


class RefreshInput(serializers.Serializer):
    refresh = serializers.CharField(max_length=4096)


class LogoutView(APIView):
    @extend_schema(request=RefreshInput, responses={204: None})
    def post(self, request):
        serializer = RefreshInput(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            if str(token["user_id"]) != str(request.user.pk):
                raise PermissionDenied("Нельзя отозвать чужой токен")
            token.blacklist()
        except TokenError:
            raise ValidationError({"refresh": "Недействительный refresh"}) from None
        return Response(status=204)


class MeView(generics.RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
